import addon from "sample/index.js";

// prints "[native code]"
console.log(addon);

// prints "string"
console.log(typeof addon);

const ret = addon.fun(123, 123, 123);

console.log(ret);
