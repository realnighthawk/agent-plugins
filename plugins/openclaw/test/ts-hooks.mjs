/**
 * ESM loader hook: remaps local .js imports to .ts so that Node's
 * --experimental-strip-types can resolve TypeScript source files during tests.
 */
export async function resolve(specifier, context, nextResolve) {
  if (specifier.endsWith(".js") && context.parentURL?.includes("/openclaw/")) {
    const tsSpecifier = specifier.slice(0, -3) + ".ts";
    try {
      return await nextResolve(tsSpecifier, context);
    } catch {
      // fall through to original specifier
    }
  }
  return nextResolve(specifier, context);
}
