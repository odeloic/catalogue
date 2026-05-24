// Auth module — the canonical definition of the auth gate.

import { Session, createSession } from "./session";

export class Auth {
  validate(token: string): boolean {
    return token.length > 0;
  }

  login(userId: string): Session {
    const session = createSession(userId);
    return session;
  }
}

export const auth = new Auth();
