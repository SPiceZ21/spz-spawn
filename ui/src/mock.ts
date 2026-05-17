export const initMockEnv = () => {
  if (import.meta.env.DEV) {
    console.log('[Mock Environment] Initialized');
    
    // Simulate opening the UI after 1 second
    setTimeout(() => {
      window.dispatchEvent(
        new MessageEvent('message', {
          data: {
            type: 'show',
            playerData: {
              name: 'SPiceZ',
              avatar: 'https://i.imgur.com/8NzA8m8.png',
              licenseClass: 'A-1',
              crew: '[SPZ]',
              playtime: 12500, // seconds
              stateText: 'IDLE'
            },
            spawns: [
              { label: 'Legion Square' },
              { label: 'Paleto Bay' },
              { label: 'Sandy Shores' },
              { label: 'LSIA Terminal' }
            ]
          }
        })
      );
    }, 1000);

    // Mock fetch for Start Spawn button
    const originalFetch = window.fetch;
    window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
      if (typeof input === 'string' && input.includes('/startSpawn')) {
        console.log('[Mock Environment] Triggered startSpawn with body:', init?.body);
        return new Response(JSON.stringify({ status: 'ok' }));
      }
      return originalFetch(input, init);
    };
  }
};
