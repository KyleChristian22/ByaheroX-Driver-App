/**
 * GPT Integration Firebase Endpoints
 * Provides HTTP endpoints for accessing GPT utilities
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Import GPT utilities
const { generateFirebaseFunction, generateUtility, generateEndpoint } = require('./gpt-utils/codeGenerator.js');
const { reviewCode, optimizeCode, refactorCode } = require('./gpt-utils/codeReviewer.js');
const { generateFunctionDocumentation, generateApiDocumentation, generateReadme, generateInlineComments } = require('./gpt-utils/documentor.js');
const { generateUnitTests, generateIntegrationTests, generateTestData, generateE2ETests } = require('./gpt-utils/testGenerator.js');

// Initialize Firebase Admin
admin.initializeApp();

/**
 * Generate Firebase Cloud Function code
 * POST /generateFunction
 */
exports.generateFunction = functions.https.onCall(async (data, context) => {
  // Check authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { requirement, context: functionContext } = data;
  
  if (!requirement) {
    throw new functions.https.HttpsError('invalid-argument', 'Requirement is required');
  }

  try {
    const result = await generateFirebaseFunction(requirement, functionContext);
    return { success: true, data: result };
  } catch (error) {
    console.error('Function generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Function generation failed', error.message);
  }
});

/**
 * Review code for improvements
 * POST /reviewCode
 */
exports.reviewCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { code, language, context: codeContext } = data;
  
  if (!code) {
    throw new functions.https.HttpsError('invalid-argument', 'Code is required');
  }

  try {
    const result = await reviewCode(code, language || 'javascript', codeContext);
    return { success: true, data: result };
  } catch (error) {
    console.error('Code review failed:', error);
    throw new functions.https.HttpsError('internal', 'Code review failed', error.message);
  }
});

/**
 * Generate documentation for code
 * POST /generateDocumentation
 */
exports.generateDocumentation = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { code, docType, context: docContext } = data;
  
  if (!code) {
    throw new functions.https.HttpsError('invalid-argument', 'Code is required');
  }

  try {
    let result;
    switch (docType) {
      case 'function':
        result = await generateFunctionDocumentation(code, docContext);
        break;
      case 'api':
        result = await generateApiDocumentation(code, docContext);
        break;
      case 'readme':
        result = await generateReadme(code, docContext);
        break;
      case 'comments':
        result = await generateInlineComments(code, docContext);
        break;
      default:
        throw new functions.https.HttpsError('invalid-argument', 'Invalid documentation type');
    }
    
    return { success: true, data: result };
  } catch (error) {
    console.error('Documentation generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Documentation generation failed', error.message);
  }
});

/**
 * Generate tests for code
 * POST /generateTests
 */
exports.generateTests = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { code, testType, context: testContext } = data;
  
  if (!code) {
    throw new functions.https.HttpsError('invalid-argument', 'Code is required');
  }

  try {
    let result;
    switch (testType) {
      case 'unit':
        result = await generateUnitTests(code, testContext);
        break;
      case 'integration':
        result = await generateIntegrationTests(code, testContext);
        break;
      case 'data':
        result = await generateTestData(code, testContext);
        break;
      case 'e2e':
        result = await generateE2ETests(code, testContext);
        break;
      default:
        throw new functions.https.HttpsError('invalid-argument', 'Invalid test type');
    }
    
    return { success: true, data: result };
  } catch (error) {
    console.error('Test generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Test generation failed', error.message);
  }
});

/**
 * Optimize existing code
 * POST /optimizeCode
 */
exports.optimizeCode = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { code, goals } = data;
  
  if (!code) {
    throw new functions.https.HttpsError('invalid-argument', 'Code is required');
  }

  try {
    const result = await optimizeCode(code, goals);
    return { success: true, data: result };
  } catch (error) {
    console.error('Code optimization failed:', error);
    throw new functions.https.HttpsError('internal', 'Code optimization failed', error.message);
  }
});

/**
 * Generate utility functions
 * POST /generateUtility
 */
exports.generateUtility = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { requirement, module } = data;
  
  if (!requirement) {
    throw new functions.https.HttpsError('invalid-argument', 'Requirement is required');
  }

  try {
    const result = await generateUtility(requirement, module || 'commuter');
    return { success: true, data: result };
  } catch (error) {
    console.error('Utility generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Utility generation failed', error.message);
  }
});

/**
 * Get GPT usage statistics
 * GET /getUsageStats
 */
exports.getUsageStats = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  try {
    // In a real implementation, you'd track usage in Firestore
    // For now, return mock data
    const stats = {
      totalRequests: 0,
      codeGeneration: 0,
      codeReview: 0,
      documentation: 0,
      testing: 0,
      lastUsed: new Date().toISOString(),
    };
    
    return { success: true, data: stats };
  } catch (error) {
    console.error('Failed to get usage stats:', error);
    throw new functions.https.HttpsError('internal', 'Failed to get usage stats', error.message);
  }
});

/**
 * Health check endpoint
 * GET /health
 */
exports.health = functions.https.onRequest(async (req, res) => {
  try {
    // Test OpenAI connection
    const { validateOpenAIConfig } = require('./gpt-utils/baseClient.js');
    const isValid = validateOpenAIConfig();
    
    res.status(200).json({
      status: 'healthy',
      openai: isValid ? 'connected' : 'disconnected',
      timestamp: new Date().toISOString(),
      module: 'commuter'
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});
