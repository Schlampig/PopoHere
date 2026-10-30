/* PopoHere · 右键菜单
 *
 * 负责：右键唤出菜单、点击外部收起、菜单项的行为。
 * 菜单项目前是 v1.0 的临时版；v2.0 会按 PRD 拆成「功能模块 + 设置模块」两组。
 *
 * 对外暴露：Popo.createMenu({ ... }) → { setHidden, isHidden, close }
 */
(function (root) {
  root.Popo = root.Popo || {};

  function createMenu(opts) {
    const el = opts.el;
    const machine = opts.machine;
    const post = opts.post || function () {};
    const getDefaultPos = opts.getDefaultPos;
    const setPos = opts.setPos;
    const onTogglePause = opts.onTogglePause || function () {};

    let hidden = false;

    function sync() {
      const node = el.ctx && el.ctx.querySelector('#mPause .state');
      if (node) node.textContent = machine.paused ? '是' : '否';
    }

    function close() {
      if (el.ctx) el.ctx.classList.remove('on');
      machine.closeMenu();
    }

    function open(x, y) {
      if (!el.ctx || machine.state === 'menu') return;
      machine.openMenu();
      el.ctx.classList.add('on');
      const r = el.ctx.getBoundingClientRect();
      el.ctx.style.left = Math.min(x, window.innerWidth - r.width - 8) + 'px';
      el.ctx.style.top = Math.min(y, window.innerHeight - r.height - 8) + 'px';
      sync();
    }

    if (el.desktop) {
      el.desktop.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        open(e.clientX, e.clientY);
      });
    }

    // 点在菜单外面就收起。用捕获阶段，避免被别的 mousedown 抢掉
    window.addEventListener('mousedown', (e) => {
      if (el.ctx && el.ctx.classList.contains('on') && !el.ctx.contains(e.target)) {
        close();
      }
    }, true);

    function bind(id, handler) {
      const node = document.getElementById(id);
      if (node) node.addEventListener('click', handler);
    }

    bind('mToggle', () => {
      hidden = !hidden;
      el.pet.classList.toggle('hidden', hidden);
      post({ type: 'hidden', value: hidden });
      close();
    });

    bind('mPause', () => {
      onTogglePause();
      sync();
      close();
    });

    bind('mFolder', () => {
      post({ type: 'openTheme' });
      close();
    });

    bind('mReset', () => {
      const dp = getDefaultPos();
      setPos(dp.left, dp.top);
      close();
    });

    bind('mQuit', () => {
      post({ type: 'quit' });
      close();
    });

    return {
      close: close,
      isHidden: () => hidden,
      setHidden: (v) => {
        hidden = !!v;
        el.pet.classList.toggle('hidden', hidden);
      },
    };
  }

  root.Popo.createMenu = createMenu;
})(typeof globalThis !== 'undefined' ? globalThis : this);
