# Connecto Legal Documents

This directory contains the legal documentation for the Connecto app, hosted on GitHub Pages.

## 📁 Structure

```
docs/
├── index.html              # Main landing page
├── privacy-policy.html     # Privacy policy
├── terms-of-service.html   # Terms of service
└── _config.yml            # Jekyll configuration
```

## 🌐 Live URLs

Once deployed, the documents will be available at:

- **Main Page**: https://velyzo.github.io/connecto/
- **Privacy Policy**: https://velyzo.github.io/connecto/privacy-policy.html
- **Terms of Service**: https://velyzo.github.io/connecto/terms-of-service.html

## 🚀 Deployment

The site is automatically deployed via GitHub Actions when changes are pushed to the main branch.

### Manual Deployment

If you need to manually deploy:

1. Go to the GitHub repository
2. Click on "Actions" tab
3. Select "Deploy GitHub Pages" workflow
4. Click "Run workflow"

## 🎨 Design

The pages follow Apple's Human Interface Guidelines with:

- **Typography**: Apple system fonts (-apple-system, SF Pro)
- **Colors**: iOS blue (#007aff) and Apple grays
- **Layout**: Responsive design with proper mobile support
- **Animations**: Smooth hover effects and transitions
- **Accessibility**: Proper contrast ratios and semantic HTML

## 📝 Content Updates

To update the legal documents:

1. Edit the respective HTML files
2. Update the "Last updated" date at the bottom
3. Commit and push changes
4. The site will automatically redeploy

## 🔧 Local Development

To test locally:

```bash
# Serve with Python
cd docs
python3 -m http.server 8080

# Or with Jekyll (if you want to use Jekyll features)
cd docs
bundle exec jekyll serve
```

Then visit http://localhost:8080

## ✅ Quality Assurance

The workflow includes:

- **HTML Validation**: Ensures valid HTML structure
- **Link Checking**: Validates internal and external links
- **Security Scanning**: Checks for potential security issues
- **Lighthouse CI**: Tests performance, accessibility, SEO
- **Responsive Testing**: Ensures mobile compatibility

## 📱 App Store Compliance

These documents meet Apple App Store requirements for:

- ✅ Privacy Policy disclosure
- ✅ Terms of Service agreement
- ✅ Data handling transparency
- ✅ User rights information
- ✅ Contact information

## 📞 Contact

For legal document questions:
- Email: legal@velyzo.com
- Privacy: privacy@velyzo.com
