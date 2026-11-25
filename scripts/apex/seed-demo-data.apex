// Demo data for the Signal Room (fictitious hospitals, surgeons, tenders and sales history).
// In a Developer Edition org (5 MB of data) the generator switches to compact mode: 18 months, ~2,000 sales rows.
// Run as an admin:  sf apex run -o <org> -f scripts/apex/seed-demo-data.apex
// Safe to re-run. Remove everything with Rules & Data > Purge demo data.

// 1. Fictitious hospital accounts (Industry = Healthcare is what the generator looks for).
Map<String, List<String>> hospitals = new Map<String, List<String>>{
    'GB' => new List<String>{ 'St Aldric University Hospital|London', 'Northgate General Hospital|Manchester',
        'Riverside Royal Infirmary|Leeds' },
    'DE' => new List<String>{ 'Universitätsklinikum Lindenberg|Hamburg', 'Klinikum Rheinhafen|Köln',
        'Städtisches Krankenhaus Altmark|Berlin' },
    'FR' => new List<String>{ 'CHU de Valmont|Toulouse', 'Hôpital Saint-Aubin|Lyon' },
    'ES' => new List<String>{ 'Hospital General de Montalbán|Valencia' },
    'IT' => new List<String>{ 'Ospedale San Bernardo|Milano' }
};
Set<String> existing = new Set<String>();
for (Account a : [SELECT Name FROM Account WHERE Industry = 'Healthcare']) {
    existing.add(a.Name);
}
List<Account> accounts = new List<Account>();
for (String country : hospitals.keySet()) {
    for (String entry : hospitals.get(country)) {
        String name = entry.substringBefore('|');
        if (!existing.contains(name)) {
            accounts.add(new Account(Name = name, BillingCity = entry.substringAfter('|'), BillingCountry = country,
                Industry = 'Healthcare', Type = 'Customer'));
        }
    }
}
insert accounts;

// 2. Rules, product lines, profiles, surgeons, tenders, signal rooms; sales in a batch that then runs the engine.
Id jobId = SignalRoomMockData.generate(true, true);
System.debug(LoggingLevel.ERROR, 'Demo data job ' + jobId + ' started; pointers appear when the engine run completes.');
