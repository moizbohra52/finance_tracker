// Entry point of the `send-push` Edge Function; the logic is in handler.ts.
import { handle } from './handler.ts';

Deno.serve((req) => handle(req, Deno.env.toObject()));
