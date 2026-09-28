import { mount } from 'svelte';
import App from './App.svelte';
// Self-hosted: the page loads nothing from any origin but its own.
import '@fontsource/jetbrains-mono/latin-800.css';
import './app.css';

mount(App, { target: document.getElementById('app')! });
