// Middleware — references auth several times but defines none of it.

import { auth } from "../auth/auth";

export function requireAuth(token: string): void {
  if (!auth.validate(token)) {
    throw new Error("auth failed");
  }
}

export function logAuth(token: string): void {
  console.log("auth check", token, auth);
}
