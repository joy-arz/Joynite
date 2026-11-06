export function actionControl(target) {
  return target?.closest?.('button:not(.card),a[href],[role="button"]') || null;
}

export function routeActionController(target, buttons, previous, onBack = () => {}) {
  const control = actionControl(target);
  if (!control) return false;
  const pressed = (index) => !!buttons[index]?.pressed && !previous[index];
  if (pressed(0)) control.click();
  else if (pressed(1)) { control.blur(); onBack(); }
  else {
    const step = pressed(14) || pressed(4) ? -1 : pressed(15) || pressed(5) ? 1 : 0;
    if (step) {
      const scope = control.closest('.software-update,aside,header,footer') || control.parentElement;
      const actions = [...scope.querySelectorAll('button:not(.card):not(:disabled),a[href]')]
        .filter(element => !element.closest('[hidden]'));
      const index = actions.indexOf(control);
      if (actions.length && index >= 0) actions[(index + step + actions.length) % actions.length].focus();
    }
  }
  return true;
}
