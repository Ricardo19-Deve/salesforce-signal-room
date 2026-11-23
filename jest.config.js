const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    // CSS-only module shared by every component (@import "c/winRoomStyles").
    moduleNameMapper: {
        ...(jestConfig.moduleNameMapper || {}),
        '^c/winRoomStyles$': '<rootDir>/force-app/main/default/lwc/winRoomStyles/winRoomStyles.css'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};
