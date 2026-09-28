const key = 'revoked_theme';

function prefersDark(): boolean {
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
}

// Shares the public page's storage key, so a choice made on one sticks on the other.
class Theme {
  choice = $state<'light' | 'dark' | null>(null);
  dark = $derived(this.choice ? this.choice === 'dark' : prefersDark());

  constructor() {
    try {
      const saved = localStorage.getItem(key);
      if (saved === 'light' || saved === 'dark') this.choice = saved;
    } catch {
      /* storage blocked: follow the system */
    }
    this.#apply();
  }

  toggle() {
    this.choice = this.dark ? 'light' : 'dark';
    try {
      localStorage.setItem(key, this.choice);
    } catch {
      /* not remembered */
    }
    this.#apply();
  }

  #apply() {
    if (this.choice) document.documentElement.dataset.theme = this.choice;
    else delete document.documentElement.dataset.theme;
  }
}

export const theme = new Theme();
