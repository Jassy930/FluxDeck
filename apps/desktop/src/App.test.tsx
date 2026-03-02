import { describe, expect, it } from 'bun:test';
import { appSections } from './App';

describe('desktop app shell', () => {
  it('renders core management panels', () => {
    const sections = appSections();
    expect(sections).toContain('Providers');
    expect(sections).toContain('Gateways');
    expect(sections).toContain('Logs');
  });
});
