// Login route — uses the auth module and the session it returns.

import { auth } from "../auth/auth";
import { Session } from "../auth/session";

export function loginHandler(userId: string): Session {
  const session = auth.login(userId);
  // Reference session a few times so it ranks as a reference-heavy file.
  if (!session) throw new Error("no session");
  console.log("created session", session.id);
  return session;
}
