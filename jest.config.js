const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    // CSS-only module shared by every component (@import "c/signalRoomStyles").
    moduleNameMapper: {
        ...(jestConfig.moduleNameMapper || {}),
        '^c/signalRoomStyles$': '<rootDir>/force-app/main/default/lwc/signalRoomStyles/signalRoomStyles.css'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};
