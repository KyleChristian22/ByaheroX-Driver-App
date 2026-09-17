/**
 * GPT Integration Firebase Endpoints - Driver Module
 * Provides HTTP endpoints for accessing GPT utilities for driver functionality
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
 * Generate Firebase Cloud Function code for driver module
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
    // Add driver-specific context
    const driverContext = {
      ...functionContext,
      module: 'driver',
      existingFunctions: 'driverLocationUpdate, acceptRide, completeRide, updateAvailability',
      database: 'Firestore',
      collections: ['drivers', 'rides', 'locations', 'earnings']
    };
    
    const result = await generateFirebaseFunction(requirement, driverContext);
    return { success: true, data: result };
  } catch (error) {
    console.error('Driver function generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Function generation failed', error.message);
  }
});

/**
 * Review driver-specific code
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
    const driverContext = {
      ...codeContext,
      module: 'driver',
      purpose: 'Driver app functionality - ride management, location tracking, earnings',
      dependencies: 'Firebase Admin, geolocation libraries, payment processing'
    };
    
    const result = await reviewCode(code, language || 'javascript', driverContext);
    return { success: true, data: result };
  } catch (error) {
    console.error('Driver code review failed:', error);
    throw new functions.https.HttpsError('internal', 'Code review failed', error.message);
  }
});

/**
 * Generate documentation for driver code
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
    const driverContext = {
      ...docContext,
      module: 'driver',
      dependencies: 'Firebase functions, geolocation, payment APIs'
    };
    
    let result;
    switch (docType) {
      case 'function':
        result = await generateFunctionDocumentation(code, driverContext);
        break;
      case 'api':
        result = await generateApiDocumentation(code, driverContext);
        break;
      case 'readme':
        result = await generateReadme(code, driverContext);
        break;
      case 'comments':
        result = await generateInlineComments(code, driverContext);
        break;
      default:
        throw new functions.https.HttpsError('invalid-argument', 'Invalid documentation type');
    }
    
    return { success: true, data: result };
  } catch (error) {
    console.error('Driver documentation generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Documentation generation failed', error.message);
  }
});

/**
 * Generate tests for driver code
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
    const driverContext = {
      ...testContext,
      module: 'driver',
      database: 'Firestore',
      auth: 'Firebase Auth',
      dependencies: 'Location services, payment processing'
    };
    
    let result;
    switch (testType) {
      case 'unit':
        result = await generateUnitTests(code, driverContext);
        break;
      case 'integration':
        result = await generateIntegrationTests(code, driverContext);
        break;
      case 'data':
        result = await generateTestData(code, driverContext);
        break;
      case 'e2e':
        result = await generateE2ETests(code, driverContext);
        break;
      default:
        throw new functions.https.HttpsError('invalid-argument', 'Invalid test type');
    }
    
    return { success: true, data: result };
  } catch (error) {
    console.error('Driver test generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Test generation failed', error.message);
  }
});

/**
 * Generate driver-specific utility functions
 * POST /generateUtility
 */
exports.generateUtility = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { requirement } = data;
  
  if (!requirement) {
    throw new functions.https.HttpsError('invalid-argument', 'Requirement is required');
  }

  try {
    const result = await generateUtility(requirement, 'driver');
    return { success: true, data: result };
  } catch (error) {
    console.error('Driver utility generation failed:', error);
    throw new functions.https.HttpsError('internal', 'Utility generation failed', error.message);
  }
});

/**
 * Optimize driver code
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
    console.error('Driver code optimization failed:', error);
    throw new functions.https.HttpsError('internal', 'Code optimization failed', error.message);
  }
});

/**
 * Health check endpoint for driver module
 * GET /health
 */
exports.health = functions.https.onRequest(async (req, res) => {
  try {
    const { validateOpenAIConfig } = require('./gpt-utils/baseClient.js');
    const isValid = validateOpenAIConfig();
    
    res.status(200).json({
      status: 'healthy',
      openai: isValid ? 'connected' : 'disconnected',
      timestamp: new Date().toISOString(),
      module: 'driver'
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});
