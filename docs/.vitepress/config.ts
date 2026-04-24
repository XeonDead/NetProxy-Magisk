import { defineConfig } from 'vitepress'

export default defineConfig({
    title: 'NetProxy',
    description: 'Android Transparent Agent Magisk/KernelSU Modules',
    lang: 'zh-CN',

    // GitHub Pages Deployment Configuration
    base: '/NetProxy-Magisk/',

    head: [
        ['link', { rel: 'icon', href: '/NetProxy-Magisk/favicon.ico' }]
    ],

    themeConfig: {
        logo: '/logo.png',

        nav: [
            { text: 'Guide', link: '/guide/introduction' },
            { text: 'Configure', link: '/config/module' },
            { text: 'WebUI', link: '/webui/overview' },
            { text: 'GitHub', link: 'https://github.com/Fanju6/NetProxy-Magisk' }
        ],

        sidebar: {
            '/guide/': [
                {
                    text: 'Introduction',
                    items: [
                        { text: 'Project Introduction', link: '/guide/introduction' },
                        { text: 'Module concept', link: '/guide/philosophy' },
                        { text: 'Install tutorials', link: '/guide/installation' },
                        { text: 'Quick Start', link: '/guide/quick-start' }
                    ]
                },
                {
                    text: 'Progress',
                    items: [
                        { text: 'Common problems', link: '/guide/faq' }
                    ]
                }
            ],
            '/config/': [
                {
                    text: 'Profile Description',
                    items: [
                        { text: 'Module Configuration', link: '/config/module' },
                        { text: 'Xray Configure', link: '/config/xray' },
                        { text: 'Route rules', link: '/config/routing' }
                    ]
                }
            ],
            '/webui/': [
                {
                    text: 'WebUI',
                    items: [
                        { text: 'Overview of functions', link: '/webui/overview' },
                        { text: 'Function Details', link: '/webui/features' }
                    ]
                }
            ]
        },

        socialLinks: [
            { icon: 'github', link: 'https://github.com/Fanju6/NetProxy-Magisk' }
        ],

        footer: {
            message: 'Based on GPL-3.0 Licensing',
            copyright: 'Copyright © 2024-present Fanju'
        },

        search: {
            provider: 'local'
        },

        outline: {
            label: 'Page Navigator',
            level: [2, 3]
        },

        docFooter: {
            prev: 'Previous Page',
            next: 'Next Page'
        },

        lastUpdated: {
            text: 'Last updated'
        },

        returnToTopLabel: 'Return Top',
        sidebarMenuLabel: 'Menu',
        darkModeSwitchLabel: 'Theme',
        lightModeSwitchTitle: 'Switch to Lightcolor Mode',
        darkModeSwitchTitle: 'Switch to Dark Mode'
    }
})
