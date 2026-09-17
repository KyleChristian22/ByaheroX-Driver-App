/**
 * Base OpenAI Client Configuration
 * Provides centralized OpenAI client setup for all GPT utilities
 */

import dotenv from 'dotenv';
import OpenAI from 'openai';

// Load environment variables from .env file
dotenv.config();

// Initialize OpenAI client with environment configuration
export const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

// Default model configuration
export const DEFAULT_MODEL = 'gpt-3.5-turbo';
export const DEFAULT_TEMPERATURE = 0.7;
export const DEFAULT_MAX_TOKENS = 2000;

/**
 * Validate OpenAI API configuration
 * @returns {boolean} True if API key is properly configured
 */
export const validateOpenAIConfig = () => {
  if (!process.env.OPENAI_API_KEY) {
    console.error('OpenAI API key is not configured in environment variables');
    return false;
  }
  return true;
};

/**
 * Create a standardized chat completion request
 * @param {string} prompt - The main prompt for GPT
 * @param {string} systemPrompt - System context/instructions
 * @param {Object} options - Additional OpenAI options
 * @returns {Promise<Object>} OpenAI API response
 */
export const createChatCompletion = async (prompt, systemPrompt = '', options = {}) => {
  if (!validateOpenAIConfig()) {
    throw new Error('OpenAI configuration is invalid');
  }

  const messages = [];
  if (systemPrompt) {
    messages.push({ role: 'system', content: systemPrompt });
  }
  messages.push({ role: 'user', content: prompt });

  const requestOptions = {
    model: DEFAULT_MODEL,
    temperature: DEFAULT_TEMPERATURE,
    max_tokens: DEFAULT_MAX_TOKENS,
    ...options,
    messages,
  };

  try {
    const response = await openai.chat.completions.create(requestOptions);
    return response;
  } catch (error) {
    console.error('OpenAI API error:', error);
    throw new Error(`OpenAI API call failed: ${error.message}`);
  }
};
