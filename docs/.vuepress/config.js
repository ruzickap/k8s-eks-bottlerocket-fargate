module.exports = {
  title: 'Amazon EKS Bottlerocket and Fargate',
  description: 'Amazon EKS Bottlerocket and Fargate',
  base: '/k8s-eks-bottlerocket-fargate/',
  head: [
    ['link', { rel: 'icon', href: 'https://kubernetes.io/images/favicon.png' }]
  ],
  themeConfig: {
    displayAllHeaders: true,
    lastUpdated: true,
    repo: 'ruzickap/k8s-eks-bottlerocket-fargate',
    docsDir: 'docs',
    docsBranch: 'main',
    editLinks: true,
    logo: 'https://kubernetes.io/images/favicon.png',
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
