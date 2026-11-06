import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { JSDOM } from 'jsdom';
import { actionControl, routeActionController } from '../src/input-context.mjs';

test('focused action owns Space and controller A without launching the library game', () => {
  const dom = new JSDOM('<section class="software-update"><button id="now">Update now</button><button id="later">Later</button></section>', { pretendToBeVisual: true });
  const now = dom.window.document.querySelector('#now'); now.focus();
  let searches = 0, activations = 0;
  now.onclick = () => activations++;
  const source = fs.readFileSync(new URL('../src/main.js', import.meta.url), 'utf8');
  const begin = source.indexOf('window.addEventListener("keydown", (event) => {');
  const end = source.indexOf('window.addEventListener("pointerdown", useKeyboard);', begin);
  const scope = {window: dom.window, HTMLElement: dom.window.HTMLElement, document: dom.window.document, useKeyboard(){}, modalOpen:()=>false, typing:()=>false, actionControl, openSearch:()=>searches++};
  vm.runInNewContext(source.slice(begin,end),scope);
  const space = new dom.window.KeyboardEvent('keydown',{key:' ',bubbles:true,cancelable:true}); now.dispatchEvent(space);
  assert.equal(searches,0); assert.equal(space.defaultPrevented,false);
  assert.equal(routeActionController(now,[{pressed:true}],[]),true);
  assert.equal(activations,1);
  routeActionController(now,[{pressed:true}],[true]); assert.equal(activations,1);
  const right = Array.from({length:16},()=>({pressed:false})); right[15].pressed=true;
  routeActionController(now,right,[]);
  assert.equal(dom.window.document.activeElement.id,'later');
  assert.equal(routeActionController(dom.window.document.body,[],[]),false);
});
