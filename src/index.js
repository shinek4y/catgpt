// @ts-check
import { Telegraf } from 'telegraf';

const bot = new Telegraf(process.env.BOT_TOKEN || '');

const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://ollama:11434';
const OLLAMA_MODEL = process.env.OLLAMA_MODEL || 'mistral';

// Store conversation context per user
const userContexts = new Map();

bot.command('start', (ctx) => {
  ctx.reply(
    `🐱 Meow! I'm CatGPT!\n\n` +
    `I'm an AI assistant. ` +
    `Just send me a message and I'll respond!\n\n` +
    `Commands:\n` +
    `/start - Show this message\n` +
    `/help - Get help\n` +
    `/clear - Clear conversation history`
  );
});

bot.command('help', (ctx) => {
  ctx.reply(
    `🐱 CatGPT Help\n\n` +
    `Just send me any message and I'll respond using AI!\n\n` +
    `Tips:\n` +
    `• I remember our conversation context\n` +
    `• Use /clear to start fresh\n` +
    `• Be patient - responses may take a moment`
  );
});

bot.command('clear', (ctx) => {
  userContexts.delete(ctx.from.id);
  ctx.reply('🧹 Conversation history cleared!');
});

/** @type {(userId: number, prompt: string) => Promise<string>} */
async function generateResponse(userId, prompt) {
  // Get or create user context
  let context = userContexts.get(userId) || [];

  // Add user message to context
  context.push({ role: 'user', content: prompt });

  // Keep only last 10 messages to manage memory
  if (context.length > 10) {
    context = context.slice(-10);
  }

  const response = await fetch(`${OLLAMA_HOST}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: OLLAMA_MODEL,
      messages: context,
      stream: false,
    }),
    signal: AbortSignal.timeout(120000), // 2 minute timeout
  });

  if (!response.ok) {
    throw new Error(`Ollama error: ${response.status}`);
  }

  const data = await response.json();
  const assistantMessage = data.message.content;

  // Add assistant response to context
  context.push({ role: 'assistant', content: assistantMessage });
  userContexts.set(userId, context);

  return assistantMessage;
}

bot.on('text', async (ctx) => {
  const userId = ctx.from.id;
  const userMessage = ctx.message.text;

  // Send typing indicator
  await ctx.sendChatAction('typing');

  // Keep sending typing indicator every 5 seconds
  const typingInterval = setInterval(() => {
    ctx.sendChatAction('typing').catch(() => { });
  }, 5000);

  try {
    const response = await generateResponse(userId, userMessage);

    // Split long messages (Telegram limit is 4096 chars)
    if (response.length > 4000) {
      const chunks = response.match(/.{1,4000}/gs) || [];
      for (const chunk of chunks) {
        await ctx.reply(chunk);
      }
    } else {
      await ctx.reply(response);
    }
  } catch (/** @type {any} */ error) {
    console.error('Error generating response:', error.message);
    let errorMsg = error.message;
    if (error.cause?.code === 'ECONNREFUSED') {
      errorMsg = 'Ollama service is not available. Please try again later.';
    }
    if (error.name === 'TimeoutError') {
      errorMsg = 'Response took too long. Please try a shorter message.';
    }
    await ctx.reply(
      `😿 Sorry, I encountered an error: ${errorMsg}\n\n` +
      `Please try again or use /clear to reset.`
    );
  } finally {
    clearInterval(typingInterval);
  }
});

// Error handling
bot.catch((err, ctx) => {
  console.error('Bot error:', err);
  ctx.reply('😿 An unexpected error occurred. Please try again.').catch(() => { });
});

// Graceful shutdown
const shutdown = () => bot.stop();
process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);

// Start bot
bot.launch().then(() => {
  console.log('🐱 CatGPT is running!');
  console.log(`📡 Ollama host: ${OLLAMA_HOST}`);
  console.log(`🤖 Model: ${OLLAMA_MODEL}`);
}).catch((err) => {
  console.error('Failed to start bot:', err);
  process.exit(1);
});

export default bot;
