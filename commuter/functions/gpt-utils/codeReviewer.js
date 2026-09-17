/**
 * GPT Code Review Utility
 * Analyzes and provides suggestions for code improvement
 */

import { createChatCompletion } from './baseClient.js';

/**
 * Review code for best practices, security, and performance
 * @param {string} code - Code to review
 * @param {string} language - Programming language (javascript, typescript, etc.)
 * @param {Object} context - Additional context about the code
 * @returns {Promise<Object>} Code review results
 */
export const reviewCode = async (code, language = 'javascript', context = {}) => {
  const systemPrompt = `You are an expert code reviewer specializing in Firebase Cloud Functions and Node.js applications.

Review code for:
- Security vulnerabilities
- Performance issues
- Best practices violations
- Code quality and maintainability
- Error handling
- Firebase-specific optimizations
- Authentication and authorization
- Database query optimization

Provide feedback in this JSON format:
{
  "overallScore": 85,
  "issues": [
    {
      "severity": "high|medium|low",
      "type": "security|performance|quality|best-practice",
      "line": 123,
      "description": "Issue description",
      "suggestion": "How to fix it",
      "codeExample": "Example fix"
    }
  ],
  "suggestions": [
    {
      "category": "optimization|security|readability",
      "description": "Suggestion description",
      "codeExample": "Example implementation"
    }
  ],
  "security": {
    "score": 90,
    "findings": ["list", "of", "security", "issues"]
  },
  "performance": {
    "score": 80,
    "findings": ["list", "of", "performance", "issues"]
  },
  "bestPractices": {
    "score": 85,
    "findings": ["list", "of", "best", "practice", "issues"]
  }
}`;

  const prompt = `Review this ${language} code:

\`\`\`${language}
${code}
\`\`\`

Context:
- Project: ByaheroX commuter app
- Module: ${context.module || 'commuter'}
- Purpose: ${context.purpose || 'Not specified'}
- Dependencies: ${context.dependencies || 'Not specified'}

Provide a comprehensive code review with specific, actionable recommendations.`;

  try {
    const response = await createChatCompletion(prompt, systemPrompt, {
      temperature: 0.2, // Low temperature for consistent analysis
      max_tokens: 3000,
    });

    const content = response.choices[0].message.content;
    
    try {
      return JSON.parse(content);
    } catch (parseError) {
      // Fallback if JSON parsing fails
      return {
        overallScore: 75,
        issues: [],
        suggestions: [],
        security: { score: 80, findings: [] },
        performance: { score: 80, findings: [] },
        bestPractices: { score: 80, findings: [] },
        rawReview: content,
      };
    }
  } catch (error) {
    console.error('Code review failed:', error);
    throw new Error(`Failed to review code: ${error.message}`);
  }
};

/**
 * Optimize code for better performance
 * @param {string} code - Code to optimize
 * @param {Object} goals - Optimization goals (speed, memory, etc.)
 * @returns {Promise<Object>} Optimized code and explanations
 */
export const optimizeCode = async (code, goals = {}) => {
  const systemPrompt = `You are an expert code optimization specialist.
Optimize code for performance, memory usage, and efficiency.

Focus on:
- Algorithm efficiency
- Memory optimization
- Firebase query optimization
- Async/await optimization
- Error handling efficiency
- Resource cleanup

Return in this JSON format:
{
  "originalCode": "Original code",
  "optimizedCode": "Optimized version",
  "improvements": [
    {
      "type": "performance|memory|security|readability",
      "description": "What was improved",
      "impact": "high|medium|low",
      "explanation": "Why it's better"
    }
  ],
  "performanceGain": "Estimated performance improvement",
  "memoryReduction": "Estimated memory usage reduction",
  "breakingChanges": false
}`;

  const prompt = `Optimize this code:

\`\`\`javascript
${code}
\`\`\`

Optimization goals:
${JSON.stringify(goals, null, 2)}

Focus on Firebase Cloud Functions best practices and performance optimization.`;

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
        originalCode: code,
        optimizedCode: content,
        improvements: [],
        performanceGain: 'Unknown',
        memoryReduction: 'Unknown',
        breakingChanges: false,
      };
    }
  } catch (error) {
    console.error('Code optimization failed:', error);
    throw new Error(`Failed to optimize code: ${error.message}`);
  }
};

/**
 * Refactor code for better structure and maintainability
 * @param {string} code - Code to refactor
 * @param {Object} requirements - Refactoring requirements
 * @returns {Promise<Object>} Refactored code and explanations
 */
export const refactorCode = async (code, requirements = {}) => {
  const systemPrompt = `You are an expert code refactoring specialist.
Refactor code for better structure, maintainability, and readability.

Refactoring goals:
- Improve code organization
- Reduce complexity
- Enhance readability
- Follow SOLID principles
- Improve testability
- Reduce code duplication

Return in this JSON format:
{
  "refactoredCode": "Refactored version",
  "changes": [
    {
      "type": "structure|readability|performance|security",
      "description": "What was changed",
      "reason": "Why it was changed"
    }
  ],
  "newFunctions": ["list", "of", "new", "helper", "functions"],
  "removedComplexity": "Description of complexity reduction",
  "testability": "How testability was improved",
  "breakingChanges": false
}`;

  const prompt = `Refactor this code:

\`\`\`javascript
${code}
\`\`\`

Refactoring requirements:
${JSON.stringify(requirements, null, 2)}`;

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
        refactoredCode: content,
        changes: [],
        newFunctions: [],
        removedComplexity: 'Unknown',
        testability: 'Unknown',
        breakingChanges: false,
      };
    }
  } catch (error) {
    console.error('Code refactoring failed:', error);
    throw new Error(`Failed to refactor code: ${error.message}`);
  }
};
