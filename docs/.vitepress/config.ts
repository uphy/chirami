import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Chirami',
  description: 'A macOS sticky-note Markdown app. Access your notes as floating windows — without breaking your flow.',
  base: '/chirami/',

  head: [
    ['link', { rel: 'icon', type: 'image/png', href: '/chirami/favicon.png' }]
  ],

  themeConfig: {
    logo: '/logo.png',

    nav: [
      { text: 'Guide', link: '/getting-started' },
      { text: 'Reference', link: '/configuration' },
      { text: 'GitHub', link: 'https://github.com/uphy/chirami' }
    ],

    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Getting Started', link: '/getting-started' },
          { text: 'Features', link: '/features' },
          { text: 'Advanced', link: '/advanced' },
          { text: 'CLI', link: '/cli' },
          { text: 'AI Integrations', link: '/ai-integrations' }
        ]
      },
      {
        text: 'Reference',
        items: [
          { text: 'Configuration', link: '/configuration' },
          { text: 'Keyboard Shortcuts', link: '/shortcuts' }
        ]
      }
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/uphy/chirami' }
    ],

    editLink: {
      pattern: 'https://github.com/uphy/chirami/edit/main/docs/:path',
      text: 'Edit this page on GitHub'
    },

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright 2026-present uphy'
    },

    search: {
      provider: 'local'
    }
  },

  srcExclude: ['performance-issues.md', 'product-vision.md']
})
