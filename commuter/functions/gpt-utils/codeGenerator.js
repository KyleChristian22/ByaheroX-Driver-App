/**
 * GPT Code Generation Utility
 * Generates Firebase functions and code based on requirements
 */

import { createChatCompletion } from './baseClient.js';

/**
 * Generate Firebase Cloud Function code
 * @param {string} requirement - Description of what the function should do
 * @param {Object} context - Project context (existing functions, database schema, etc.)
 * @returns {Promise<Object>} Generated code with metadata
 */
export const generateFirebaseFunction = async (requirement, context = {}) => {
  const systemPrompt = `You are an expert Firebase Cloud Functions developer. 
Generate complete, production-ready Firebase functions that follow best practices.

Requirements:
- Use modern JavaScript (ES6+) syntax
- Include proper error handling and logging
- Follow Firebase security guidelines
- Include JSDoc comments
- Make functions testable and modular
- Use async/await where appropriate
- Include proper environment variable usage

Context:
- Project: ByaheroX commuter app
- Database: Firebase Firestore
- Authentication: Firebase Auth
- Existing functions: ${context.existingFunctions || 'None provided'}

Return the response in this JSON format:
{
  "functionName": "generatedFunctionName",
  "description": "Brief description of what the function does",
  "code": "Complete function code with imports and exports",
  "dependencies": ["list", "of", "additional", "packages", "needed"],
  "environmentVars": ["list", "of", "environment", "variables", "needed"],
  "testCases": ["example", "test", "cases"]
}`;

  const prompt = `Generate a Firebase Cloud Function for this requirement:
${requirement}

Additional context:
${JSON.stringify(context, null, 2)}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.3, // Lower temperature for more consistent code
      max_tokens: 3000,
    });

    const content = response.choices[0].message.content;
    
    // Try to parse as JSON, fallback to raw content if parsing fails
    try {
      return JSON.parse(content);
    } catch (parseError) {
      return {
        functionName: 'generatedFunction',
        description: 'Generated function',
        code: content,
        dependencies: [],
        environmentVars: [],
        testCases: [],
      };
    }
  } catch (error) {
    console.error('Code generation failed:', error);
    throw new Error(`Failed to generate function: ${error.message}`);
  }
};

/**
 * Generate utility/helper functions
 * @param {string} requirement - Description of utility needed
 * @param {string} module - Target module (commuter, driver, admin)
 * @returns {Promise<Object>} Generated utility code
 */
export const generateUtility = async (requirement, module = 'commuter') => {
  const systemPrompt = `You are an expert JavaScript utility developer.
Generate reusable utility functions for the ByaheroX ${module} module.

Requirements:
- Create pure functions when possible
- Include comprehensive JSDoc documentation
- Add input validation and error handling
- Include example usage
- Make functions testable
- Follow DRY principles

Return in JSON format:
{
  "utilityName": "utilityName",
  "description": "What this utility does",
  "code": "Complete utility code",
  "usage": "Example usage code",
  "dependencies": ["list", "of", "packages", "needed"]
}`;

  const prompt = `Generate a utility function for:
${requirement}
Module: ${module}`;

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
        utilityName: 'generatedUtility',
        description: 'Generated utility',
        code: content,
        usage: '// Usage example',
        dependencies: [],
      };
    }
  } catch (error) {
    console.error('Utility generation failed:', error);
    throw new Error(`Failed to generate utility: ${error.message}`);
  }
};

/**
 * Generate API endpoint code
 * @param {string} endpoint - Description of API endpoint
 * @param {Object} schema - Request/response schema
 * @returns {Promise<Object>} Generated endpoint code
 */
export const generateEndpoint = async (endpoint, schema = {}) => {
  const systemPrompt = `You are an expert REST API developer.
Generate Firebase HTTP endpoints with proper validation and error handling.

Requirements:
- Use Firebase functions.https.onCall() or functions.https.onRequest()
- Include request validation
- Add proper HTTP status codes
- Include error responses
- Add input sanitization
- Include API documentation
- Handle authentication if needed

Return in JSON format:
{
  "endpointName": "endpointName",
  "method": "GET|POST|PUT|DELETE",
  "path": "/api/endpoint",
  "code": "Complete endpoint code",
  "requestSchema": "Request body schema",
  "responseSchema": "Response body schema",
  "authentication": "auth method if needed"
}`;

  const prompt = `Generate an API endpoint for:
${endpoint}

Request/Response Schema:
${JSON.stringify(schema, null, 2)}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.3,
      max_tokens: 2500,
    });

    const content = response.choices[0].message.content;
    
    try {
      return JSON.parse(content);
    } catch (parseError) {
      return {
        endpointName: 'generatedEndpoint',
        method: 'POST',
        path: '/api/endpoint',
        code: content,
        requestSchema: {},
        responseSchema: {},
        authentication: 'none',
      };
    }
  } catch (error) {
    console.error('Endpoint generation failed:', error);
    throw new Error(`Failed to generate endpoint: ${error.message}`);
  }
};
