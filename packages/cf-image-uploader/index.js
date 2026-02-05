import addModule from "./out/main.wasm"

export async function onRequest() {
  const addInstance = await WebAssembly.instantiate(addModule);
  return new Response(
    `Result: ${addInstance.exports.add(20, 1)}`
  );
}
