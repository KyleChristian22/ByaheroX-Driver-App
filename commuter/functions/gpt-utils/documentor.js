/**
 * GPT Documentation Generator Utility
 * Generates comprehensive documentation for code and APIs
 */

import { createChatCompletion } from './baseClient.js';

/**
 * Generate comprehensive documentation for a function
 * @param {string} code - Function code to document
 * @param {Object} context - Context about the function
 * @returns {Promise<Object>} Generated documentation
 */
export const generateFunctionDocumentation = async (code, context = {}) => {
  const systemPrompt = `You are an expert technical documentation writer.
Generate comprehensive documentation for Firebase Cloud Functions.

Documentation requirements:
- Clear, concise descriptions
- Parameter documentation with types
- Return value documentation
- Usage examples
- Error scenarios
- Security considerations
- Performance notes
- Related functions

Return in this JSON format:
{
  "functionName": "functionName",
  "summary": "Brief one-line description",
  "description": "Detailed description of what the function does",
  "parameters": [
    {
      "name": "paramName",
      "type": "string|object|number|boolean",
      "description": "Parameter description",
      "required": true,
      "example": "example value"
    }
  ],
  "returns": {
    "type": "return type",
    "description": "What the function returns",
    "example": "example return value"
  },
  "usage": {
    "basic": "Basic usage example",
    "advanced": "Advanced usage example"
  },
  "errors": [
    {
      "type": "ErrorType",
      "description": "When this error occurs",
      "solution": "How to handle it"
    }
  ],
  "security": "Security considerations",
  "performance": "Performance notes",
  "relatedFunctions": ["list", "of", "related", "functions"],
  "version": "1.0.0",
  "author": "GPT Assistant"
}`;

  const prompt = `Generate documentation for this function:

\`\`\`javascript
${code}
\`\`\`

Context:
- Module: ${context.module || 'commuter'}
- Project: ByaheroX
- Purpose: ${context.purpose || 'Not specified'}
- Dependencies: ${context.dependencies || 'Not specified'}`;

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
        functionName: 'unknown',
        summary: 'Generated documentation',
        description: content,
        parameters: [],
        returns: {},
        usage: {},
        errors: [],
        security: '',
        performance: '',
        relatedFunctions: [],
        version: '1.0.0',
        author: 'GPT Assistant',
      };
    }
  } catch (error) {
    console.error('Documentation generation failed:', error);
    throw new Error(`Failed to generate documentation: ${error.message}`);
  }
};

/**
 * Generate API documentation for endpoints
 * @param {string} endpointCode - Endpoint function code
 * @param {Object} apiInfo - API information
 * @returns {Promise<Object>} API documentation
 */
export const generateApiDocumentation = async (endpointCode, apiInfo = {}) => {
  const systemPrompt = `You are an expert API documentation writer.
Generate comprehensive API documentation for Firebase endpoints.

Documentation requirements:
- OpenAPI/Swagger compatible format
- Clear endpoint descriptions
- Request/response schemas
- Authentication requirements
- Error codes and responses
- Rate limiting information
- Example requests/responses
- Testing examples

Return in this JSON format:
{
  "endpoint": "/api/endpoint",
  "method": "POST",
  "summary": "Brief endpoint description",
  "description": "Detailed endpoint description",
  "authentication": {
    "required": true,
    "type": "Bearer token",
    "description": "Authentication requirements"
  },
  "request": {
    "schema": "Request body schema",
    "headers": ["required", "headers"],
    "example": "Example request body"
  },
  "response": {
    "success": {
      "code": 200,
      "schema": "Success response schema",
      "example": "Success response example"
    },
    "errors": [
      {
        "code": 400,
        "description": "Error description",
        "schema": "Error response schema",
        "example": "Error response example"
      }
    ]
  },
  "rateLimit": {
    "requests": 100,
    "window": "1 hour"
  },
  "testing": {
    "curl": "Curl command example",
    "javascript": "JavaScript fetch example"
  }
}`;

  const prompt = `Generate API documentation for this endpoint:

\`\`\`javascript
${endpointCode}
\`\`\`

API Information:
${JSON.stringify(apiInfo, null, 2)}`;

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
        endpoint: '/api/endpoint',
        method: 'POST',
        summary: 'Generated API documentation',
        description: content,
        authentication: { required: false, type: 'none' },
        request: {},
        response: { success: {}, errors: [] },
        rateLimit: {},
        testing: {},
      };
    }
  } catch (error) {
    console.error('API documentation generation failed:', error);
    throw new Error(`Failed to generate API documentation: ${error.message}`);
  }
};

/**
 * Generate README documentation for a module
 * @param {Array} functions - List of functions in the module
 * @param {Object} moduleInfo - Module information
 * @returns {Promise<Object>} README documentation
 */
export const generateReadme = async (functions, moduleInfo = {}) => {
  const systemPrompt = `You are an expert technical writer.
Generate comprehensive README documentation for Firebase Cloud Functions modules.

README requirements:
- Clear project overview
- Installation instructions
- Usage examples
- API documentation
- Development setup
- Testing instructions
- Deployment guide
- Contributing guidelines
- License information

Return in this JSON format:
{
  "title": "Module Title",
  "description": "Module description",
  "installation": {
    "prerequisites": ["list", "of", "prerequisites"],
    "steps": ["step", "1", "step", "2"]
  },
  "usage": {
    "basic": "Basic usage example",
    "advanced": "Advanced usage example"
  },
  "api": {
    "endpoints": ["list", "of", "endpoints"],
    "authentication": "Auth requirements"
  },
  "development": {
    "setup": "Development setup instructions",
    "testing": "Testing instructions"
  },
  "deployment": {
    "local": "Local deployment",
    "production": "Production deployment"
  },
  "contributing": "Contributing guidelines",
  "license": "MIT",
  "changelog": "Recent changes"
}`;

  const prompt = `Generate README documentation for a module with these functions:

${functions.map(fn => `- ${fn.name}: ${fn.description}`).join('\n')}

Module Information:
${JSON.stringify(moduleInfo, null, 2)}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.4,
      max_tokens: 3000,
    });

    const content = response.choices[0].message.content;
    
    try {
      return JSON.parse(content);
    } catch (parseError) {
      return {
        title: 'Generated Module',
        description: content,
        installation: {},
        usage: {},
        api: {},
        development: {},
        deployment: {},
        contributing: '',
        license: 'MIT',
        changelog: '',
      };
    }
  } catch (error) {
    console.error('README generation failed:', error);
    throw new Error(`Failed to generate README: ${error.message}`);
  }
};

/**
 * Generate inline code comments
 * @param {string} code - Code to add comments to
 * @param {Object} options - Comment generation options
 * @returns {Promise<string>} Code with added comments
 */
export const generateInlineComments = async (code, options = {}) => {
  const systemPrompt = `You are an expert code commenter.
Add meaningful inline comments to explain complex logic, business rules, and technical decisions.

Commenting guidelines:
- Explain WHY, not WHAT
- Comment complex business logic
- Explain non-obvious technical decisions
- Add TODO comments for future improvements
- Include performance considerations
- Mark security-sensitive areas
- Keep comments concise and clear

Return only the commented code, no additional text.`;

  const prompt = `Add meaningful inline comments to this code:

\`\`\`javascript
${code}
\`\`\`

Options:
${JSON.stringify(options, null, 2)}`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.2,
      max_tokens: 2000,
    });

    return response.choices[0].message.content;
  } catch (error) {
    console.error('Inline comment generation failed:', error);
    throw new Error(`Failed to generate inline comments: ${error.message}`);
  }
};
