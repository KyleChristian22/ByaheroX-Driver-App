/**
 * GPT Test Generation Utility
 * Generates comprehensive test cases for Firebase functions
 */

import { createChatCompletion } from './baseClient.js';

/**
 * Generate unit tests for a function
 * @param {string} functionCode - Function code to test
 * @param {Object} context - Context about the function
 * @returns {Promise<Object>} Generated test suite
 */
export const generateUnitTests = async (functionCode, context = {}) => {
  const systemPrompt = `You are an expert test engineer specializing in Firebase Cloud Functions.
Generate comprehensive unit tests using Jest or Mocha testing frameworks.

Test requirements:
- Test all success scenarios
- Test all error scenarios
- Test edge cases and boundary conditions
- Mock external dependencies (Firebase, APIs)
- Include setup and teardown
- Test authentication and authorization
- Test input validation
- Include performance tests where relevant

Return in this JSON format:
{
  "testFramework": "jest|mocha",
  "dependencies": ["jest", "firebase-functions-test", "@firebase/testing"],
  "setupCode": "Test setup and mocking code",
  "testSuite": {
    "describe": "Test suite description",
    "tests": [
      {
        "describe": "Test group description",
        "testName": "Specific test name",
        "testCode": "Complete test code",
        "scenario": "What this test covers",
        "expected": "Expected outcome"
      }
    ]
  },
  "mocks": {
    "firebase": "Firebase mocking setup",
    "external": "External API mocking"
  },
  "coverage": {
    "lines": "Expected line coverage",
    "branches": "Expected branch coverage",
    "functions": "Expected function coverage"
  }
}`;

  const prompt = `Generate unit tests for this function:

\`\`\`javascript
${functionCode}
\`\`\`

Context:
- Module: ${context.module || 'commuter'}
- Dependencies: ${context.dependencies || 'Not specified'}
- Database: ${context.database || 'Firestore'}
- Authentication: ${context.auth || 'Firebase Auth'}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.2,
      max_tokens: 3000,
    });

    const content = response.choices[0].message.content;
    
    try {
      return JSON.parse(content);
    } catch (parseError) {
      return {
        testFramework: 'jest',
        dependencies: ['jest'],
        setupCode: '// Test setup',
        testSuite: { describe: 'Generated tests', tests: [] },
        mocks: {},
        coverage: {},
        rawTests: content,
      };
    }
  } catch (error) {
    console.error('Unit test generation failed:', error);
    throw new Error(`Failed to generate unit tests: ${error.message}`);
  }
};

/**
 * Generate integration tests for API endpoints
 * @param {string} endpointCode - Endpoint function code
 * @param {Object} apiSpec - API specification
 * @returns {Promise<Object>} Generated integration tests
 */
export const generateIntegrationTests = async (endpointCode, apiSpec = {}) => {
  const systemPrompt = `You are an expert integration test engineer.
Generate comprehensive integration tests for Firebase HTTP endpoints.

Integration test requirements:
- Test complete request/response cycles
- Test authentication flows
- Test database operations
- Test error handling
- Test rate limiting
- Test CORS handling
- Test with real Firebase emulator
- Include performance benchmarks

Return in this JSON format:
{
  "testFramework": "jest|supertest",
  "dependencies": ["jest", "supertest", "firebase-functions-test"],
  "setupCode": "Integration test setup with Firebase emulator",
  "testSuite": {
    "describe": "Integration test suite",
    "tests": [
      {
        "testName": "Test name",
        "testCode": "Complete integration test",
        "scenario": "Test scenario description",
        "request": "Test request details",
        "expectedResponse": "Expected response",
        "assertions": ["list", "of", "assertions"]
      }
    ]
  },
  "performance": {
    "benchmarks": ["Performance test scenarios"],
    "thresholds": "Performance thresholds"
  },
  "security": {
    "authTests": ["Authentication test scenarios"],
    "inputValidation": ["Input validation tests"]
  }
}`;

  const prompt = `Generate integration tests for this endpoint:

\`\`\`javascript
${endpointCode}
\`\`\`

API Specification:
${JSON.stringify(apiSpec, null, 2)}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.2,
      max_tokens: 2500,
    });

    const content = response.choices[0].message.content;
    
    try {
      return JSON.parse(content);
    } catch (parseError) {
      return {
        testFramework: 'jest',
        dependencies: ['jest', 'supertest'],
        setupCode: '// Integration test setup',
        testSuite: { describe: 'Generated integration tests', tests: [] },
        performance: {},
        security: {},
        rawTests: content,
      };
    }
  } catch (error) {
    console.error('Integration test generation failed:', error);
    throw new Error(`Failed to generate integration tests: ${error.message}`);
  }
};

/**
 * Generate test data for testing scenarios
 * @param {Object} schema - Data schema
 * @param {Object} requirements - Test data requirements
 * @returns {Promise<Object>} Generated test data
 */
export const generateTestData = async (schema, requirements = {}) => {
  const systemPrompt = `You are an expert test data generator.
Generate realistic test data for various testing scenarios.

Test data requirements:
- Valid test cases
- Invalid test cases
- Edge cases and boundary values
- Performance testing data
- Security testing data
- Internationalization data
- Large datasets for stress testing

Return in this JSON format:
{
  "validData": [
    {
      "description": "Valid test case description",
      "data": "Valid test data object"
    }
  ],
  "invalidData": [
    {
      "description": "Invalid test case description",
      "data": "Invalid test data object",
      "expectedError": "Expected error type"
    }
  ],
  "edgeCases": [
    {
      "description": "Edge case description",
      "data": "Edge case data"
    }
  ],
  "performanceData": {
    "small": "Small dataset",
    "medium": "Medium dataset",
    "large": "Large dataset"
  },
  "securityData": [
    {
      "type": "xss|sql-injection|auth-bypass",
      "data": "Malicious test data",
      "description": "Security test scenario"
    }
  ]
}`;

  const prompt = `Generate test data for this schema:

${JSON.stringify(schema, null, 2)}

Requirements:
${JSON.stringify(requirements, null, 2)}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.3,
      max_tokens: 2000,
    });

    const content = response.choices[0].message.content;
    
    try {
      return JSON.parse(content);
    } catch (parseError) {
      return {
        validData: [],
        invalidData: [],
        edgeCases: [],
        performanceData: {},
        securityData: [],
        rawData: content,
      };
    }
  } catch (error) {
    console.error('Test data generation failed:', error);
    throw new Error(`Failed to generate test data: ${error.message}`);
  }
};

/**
 * Generate end-to-end test scenarios
 * @param {Array} userStories - List of user stories
 * @param {Object} systemInfo - System information
 * @returns {Promise<Object>} E2E test scenarios
 */
export const generateE2ETests = async (userStories, systemInfo = {}) => {
  const systemPrompt = `You are an expert end-to-end test engineer.
Generate comprehensive E2E test scenarios for user workflows.

E2E test requirements:
- Complete user journey testing
- Multi-service integration testing
- Real browser automation scenarios
- Mobile app testing scenarios
- Performance testing under load
- Error recovery testing
- Accessibility testing
- Cross-browser testing

Return in this JSON format:
{
  "testFramework": "cypress|playwright|selenium",
  "dependencies": ["cypress", "playwright", "@testing-library"],
  "setupCode": "E2E test setup and configuration",
  "testScenarios": [
    {
      "userStory": "User story description",
      "testName": "E2E test name",
      "steps": [
        {
          "action": "User action",
          "expected": "Expected result",
          "code": "Test step code"
        }
      ],
      "assertions": ["list", "of", "assertions"],
      "testData": "Required test data"
    }
  ],
  "performance": {
    "scenarios": ["Performance test scenarios"],
    "metrics": ["Performance metrics to track"]
  },
  "accessibility": {
    "tests": ["Accessibility test scenarios"],
    "standards": ["WCAG standards to test"]
  }
}`;

  const prompt = `Generate E2E test scenarios for these user stories:

${userStories.map(story => `- ${story.title}: ${story.description}`).join('\n')}

System Information:
${JSON.stringify(systemInfo, null, 2)}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.3,
      max_tokens: 3000,
    });

    const content = response.choices[0].message.content;
    
    try {
      return JSON.parse(content);
    } catch (parseError) {
      return {
        testFramework: 'cypress',
        dependencies: ['cypress'],
        setupCode: '// E2E test setup',
        testScenarios: [],
        performance: {},
        accessibility: {},
        rawTests: content,
      };
    }
  } catch (error) {
    console.error('E2E test generation failed:', error);
    throw new Error(`Failed to generate E2E tests: ${error.message}`);
  }
};
