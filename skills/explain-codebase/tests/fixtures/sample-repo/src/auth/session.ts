// Session module — defines the session type and the helpers around it.

export interface Session {
  id: string;
  userId: string;
  expiresAt: Date;
}

export function createSession(userId: string): Session {
  return {
    id: cryptoRandom(),
    userId,
    expiresAt: new Date(Date.now() + 60 * 60 * 1000),
  };
}

export function invalidateSession(session: Session): void {
  session.expiresAt = new Date(0);
}

function cryptoRandom(): string {
  return Math.random().toString(36).slice(2);
}
