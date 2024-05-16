module.exports = {
  title: 'Amazon EKS Bottlerocket and Fargate',
  description: 'Amazon EKS Bottlerocket and Fargate',
  base: '/k8s-eks-bottlerocket-fargate/',
  head: [
    ['link', { rel: 'icon', href: 'https://raw.githubusercontent.com/kubernetes/kubernetes/d9a58a39b69a0eaec5797e0f7a0f9472b4829ab0/logo/logo.svg' }]
  ],
  themeConfig: {
    displayAllHeaders: true,
    lastUpdated: true,
    repo: 'ruzickap/k8s-eks-bottlerocket-fargate',
    docsDir: 'docs',
    docsBranch: 'main',
    editLinks: true,
    logo: 'https://raw.githubusercontent.com/kubernetes/kubernetes/d9a58a39b69a0eaec5797e0f7a0f9472b4829ab0/logo/logo.svg',
    nav: [
      { text: 'Home', link: '/' },
      {
        text: 'Links',
        items: [
          { text: 'Amazon EKS', link: 'https://aws.amazon.com/eks/' },
          { text: 'Bottlerocket', link: 'https://aws.amazon.com/bottlerocket/' }
        ]
      }
    ],
    sidebar: [
      '/',
      '/part-01/',
      '/part-02/',
      '/part-03/',
      '/part-04/',
      '/part-05/',
      '/part-06/',
      '/part-07/',
      '/part-08/',
      '/part-09/',
      '/part-10/',
      '/part-11/',
      '/part-12/',
      '/part-13/'
    ]
  },
  plugins: [
    '@vuepress/medium-zoom',
    '@vuepress/back-to-top',
    'reading-progress',
    'seo',
    'smooth-scroll'
  ]
}
