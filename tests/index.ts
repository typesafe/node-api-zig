import addon from "sample/index.js";

// prints "[native code]"
console.log(addon);

// prints "string"
console.log(typeof addon);

const ret = addon.nfun(123, true);
console.log(ret);

// const p=  await addon.afun(123, 123, 123);
// console.log(p);
