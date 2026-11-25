/**
 * GenAI enrichment for the Signal Room: turns a rule-based pointer into the "why and what" for the rep, and
 * prepares the facilitator's briefing for a weekly signal room.
 *
 * Where to configure: create a Named Credential called Signal_Room_LLM that points at an OpenAI-compatible
 * chat completions API (e.g. https://api.openai.com) with an External Credential holding the API key.
 * No key is stored in this repository or in Apex.
 * Gotchas: without the named credential, or when the call fails, a rule-based summary is returned so the portal
 * keeps working. The model only writes the explanation; the opportunity itself always comes from the rules.
 */
public with sharing class SignalRoomAIService {

    public static final String NAMED_CREDENTIAL = 'Signal_Room_LLM';
    private static final String PATH = '/v1/chat/completions';
    private static final String MODEL = 'gpt-4o-mini';
    private static final Integer TIMEOUT_MS = 60000;

    @TestVisible
    static Boolean forceConfigured = false;

    public class Result {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Boolean aiGenerated = false;
        @AuraEnabled public String error;
        @AuraEnabled public Map<String, Object> content = new Map<String, Object>();
    }

    public static Boolean isConfigured() {
        return forceConfigured || [SELECT COUNT() FROM NamedCredential WHERE DeveloperName = :NAMED_CREDENTIAL] > 0;
    }

    /** Insight for one pointer: why, what, next best actions, talking points, questions, risks. */
    public static Result enrichPointer(SR_Pointer__c p, SR_Account_Profile__c profile) {
        String systemPrompt = 'You are a senior sales coach for a medical device company (orthopaedic reconstruction: '
            + 'knees, hips, robotics). You turn data-driven opportunity pointers into concrete, credible guidance for a '
            + 'field sales rep preparing an account plan. Be specific, practical and concise. Never invent numbers that '
            + 'are not in the input. Answer in English. Respond ONLY with a JSON object.';
        String user = 'POINTER\n'
            + 'Type: ' + p.Type__c + ' (' + p.Category__c + ')\n'
            + 'Title: ' + p.Title__c + '\n'
            + 'Account: ' + p.Account__r?.Name + (profile == null ? '' : ' | ' + profile.Country__c + ' | '
                + profile.Segment__c + ' | ' + profile.Size_Band__c + ' | knees/yr ' + profile.Knee_Procedures__c
                + ' | hips/yr ' + profile.Hip_Procedures__c + ' | surgical robot: ' + profile.Has_Robot__c) + '\n'
            + 'Product line: ' + (p.Product_Line__r?.Name == null ? '-' : p.Product_Line__r.Name) + '\n'
            + 'Surgeon: ' + (p.Surgeon__r?.Name == null ? '-' : p.Surgeon__r.Name) + '\n'
            + 'Value at stake per year (EUR): ' + p.Value_At_Stake__c + '\n'
            + 'Rule rationale: ' + p.Rationale__c + '\n'
            + 'Evidence facts: ' + factsOf(p.Evidence__c) + '\n'
            + 'Company playbook for this pointer type: ' + p.Next_Best_Action__c + '\n\n'
            + 'Return JSON with keys:\n'
            + '"why": 2-3 sentences explaining why this opportunity exists and why now,\n'
            + '"what": 1-2 sentences describing the concrete offer or play,\n'
            + '"nextBestActions": exactly 3 short imperative actions with an owner role and timing,\n'
            + '"talkingPoints": 3 talking points for the surgeon or procurement conversation,\n'
            + '"discoveryQuestions": 3 probing questions to validate the pointer with the customer,\n'
            + '"risks": 2 risks or reasons the pointer could be wrong.';
        Result r = call(systemPrompt, user, 900);
        if (!r.success) {
            r.content = fallbackPointer(p);
            r.success = true;
        }
        return r;
    }

    /** Short briefing for the facilitator of a weekly signal room. */
    public static Result sessionBrief(String team, String agendaText) {
        String systemPrompt = 'You prepare the facilitator of a weekly sales signal room at a medical device company. '
            + 'The signal room asks the same 7 questions every week. Summarise the data into a crisp briefing. Do not '
            + 'invent data. Answer in English. Respond ONLY with a JSON object.';
        String user = 'TEAM: ' + team + '\nAGENDA DATA:\n' + agendaText.left(12000) + '\n\n'
            + 'Return JSON with keys: "headline" (one sentence), "highlights" (max 4 bullets), '
            + '"focusAccounts" (max 3 bullets naming account and why), "decisionsNeeded" (max 3 bullets), '
            + '"challengeQuestions" (3 questions the challenger should ask).';
        Result r = call(systemPrompt, user, 700);
        if (!r.success) {
            r.content = new Map<String, Object>{
                'headline' => 'Rule-based briefing (AI not configured): review the agenda sections in order.',
                'highlights' => new List<String>{ agendaText.left(400) },
                'focusAccounts' => new List<String>(),
                'decisionsNeeded' => new List<String>(),
                'challengeQuestions' => new List<String>{
                    'Which accepted pointers still have no owner action?',
                    'What blocks the oldest open opportunity?',
                    'Which tender needs a bid decision this week?'
                }
            };
            r.success = true;
        }
        return r;
    }

    private static Result call(String systemPrompt, String user, Integer maxTokens) {
        Result r = new Result();
        if (!isConfigured()) {
            r.error = 'AI not configured: create the ' + NAMED_CREDENTIAL + ' named credential.';
            return r;
        }
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL + PATH);
            req.setMethod('POST');
            req.setTimeout(TIMEOUT_MS);
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(new Map<String, Object>{
                'model' => MODEL,
                'max_tokens' => maxTokens,
                'temperature' => 0.3,
                'response_format' => new Map<String, Object>{ 'type' => 'json_object' },
                'messages' => new List<Object>{
                    new Map<String, Object>{ 'role' => 'system', 'content' => systemPrompt },
                    new Map<String, Object>{ 'role' => 'user', 'content' => user }
                }
            }));
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                r.error = 'AI service error ' + res.getStatusCode() + ': ' + res.getBody().left(300);
                return r;
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> choices = (List<Object>) body.get('choices');
            Map<String, Object> message = (Map<String, Object>) ((Map<String, Object>) choices[0]).get('message');
            r.content = (Map<String, Object>) JSON.deserializeUntyped((String) message.get('content'));
            r.success = true;
            r.aiGenerated = true;
        } catch (Exception e) {
            r.error = 'AI call failed: ' + e.getMessage();
        }
        return r;
    }

    @TestVisible
    private static Map<String, Object> fallbackPointer(SR_Pointer__c p) {
        List<String> actions = new List<String>();
        if (String.isNotBlank(p.Next_Best_Action__c)) {
            for (String s : p.Next_Best_Action__c.split('\\. ')) {
                if (String.isNotBlank(s) && actions.size() < 3) {
                    actions.add(s.removeEnd('.') + '.');
                }
            }
        }
        return new Map<String, Object>{
            'why' => p.Rationale__c,
            'what' => p.Title__c,
            'nextBestActions' => actions,
            'talkingPoints' => new List<String>(),
            'discoveryQuestions' => new List<String>{
                'Has anything changed in the procedure mix or surgeon team recently?',
                'Which alternative products are being used today, and why?',
                'What would it take to consolidate this volume with us?'
            },
            'risks' => new List<String>{ 'The data may lag behind recent orders.', 'Volume may be covered by a framework we are not on.' },
            'note' => 'Rule-based summary - connect the Signal_Room_LLM named credential for AI insights.'
        };
    }

    private static String factsOf(String evidenceJson) {
        if (String.isBlank(evidenceJson)) {
            return '-';
        }
        try {
            Map<String, Object> ev = (Map<String, Object>) JSON.deserializeUntyped(evidenceJson);
            return JSON.serialize(ev.get('facts'));
        } catch (Exception e) {
            return '-';
        }
    }
}
