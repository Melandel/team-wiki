# Azure Pipeline `SourceHubWiki-Scheduled-Chores`
* Triggers (only schedule builds if the source or pipeline has changed):
  * Tuesday to Saturday, 04:20
  * Monday to Friday, 13:37
* PAT giving the build access to source code
  * In `AzureDevOpsProject > Settings > Service connections > AzureDevOpsProject wiki`
  * `Edit`
  * `Password/Token (optional)`

## Get sources (shallow fetch)

## Agent Job `Automate menial wiki content updates` using YAML
```yaml
pool:
  name: Azure Pipelines
steps:
- powershell: |
   git config --global user.name "Project Collection Build Service (organization)"
   git config --global user.email "agent.vsts@organization.fr"
   git checkout wikiMaster
  displayName: 'Git Config'

- powershell: |
   $catalogOfTerms = (get-childitem -recurse -Directory -Filter '*catalog-of-terms').FullName
   $catalogOfTermsOrderFile = (get-childitem $catalogOfTerms .order).FullName
   
   $sortedCatalogOfTermsOrderFileContent = Get-Content $catalogOfTermsOrderFile | Sort
   
   $sortedCatalogOfTermsOrderFileContent > $catalogOfTermsOrderFile
   
   git add -A
   git diff-index --quiet HEAD;$nochanges=$?
   if (-Not $nochanges) {
     git status
     git commit -m "chore (index pages): sort catalog-of-terms alphabetically ***NO_CI***"
   }
  displayName: 'Sort Catalog-of-terms alphabetically'

- powershell: |
   (Get-ChildItem -Recurse -Filter *.order) |
     % {. .\.scripts\Build-MarkdownListingSectionFromRecursiveChildrenPages.ps1 (Resolve-Path -LiteralPath $_.FullName -Relative)}
   
   git add -A
   git diff-index --quiet HEAD;$nochanges=$?
   if (-Not $nochanges) {
     git status
     git commit -m "chore (index pages): regenerate <!-- Listing --> section in all parent pages ***NO_CI***"
   }
  displayName: 'Regenerate  <!-- Listing --> Section in all Parent Pages'

- powershell: |
   git pull
   git push -u "https://$Env:SYSTEM_ACCESSTOKEN@organization.visualstudio.com/AzureDevopsProjectName/_git/AzureDevopsProjectName.wiki"
  displayName: 'Git Push'
```
## Agent Job `Automate menial wiki content updates` without YAML
* Run on agent
* Allow scripts to access to OAuth token

### Git config
```ps1
git config --global user.name "Project Collection Build Service (organization)"
git config --global user.email "agent.vsts@organization.fr"
git checkout wikiMaster
```

### Sort Catalog-of-terms alphabetically
```ps1
$catalogOfTerms = (get-childitem -recurse -Directory -Filter '*catalog-of-terms').FullName
$catalogOfTermsOrderFile = (get-childitem $catalogOfTerms .order).FullName

$sortedCatalogOfTermsOrderFileContent = Get-Content $catalogOfTermsOrderFile | Sort

$sortedCatalogOfTermsOrderFileContent > $catalogOfTermsOrderFile

git add -A
git diff-index --quiet HEAD;$nochanges=$?
if (-Not $nochanges) {
  git status
  git commit -m "chore (index pages): sort catalog-of-terms alphabetically ***NO_CI***"
}
```

### Regenerate  `<!-- Listing -->` Section in all Parent Pages
```ps1
(Get-ChildItem -Recurse -Filter *.order) |
  % {. .\.scripts\Build-MarkdownListingSectionFromRecursiveChildrenPages.ps1 (Resolve-Path -LiteralPath $_.FullName -Relative)}

git add -A
git diff-index --quiet HEAD;$nochanges=$?
if (-Not $nochanges) {
  git status
  git commit -m "chore (index pages): regenerate <!-- Listing --> section in all parent pages ***NO_CI***"
}
```

### Git Push
```ps1
git pull
git push -u "https://$Env:SYSTEM_ACCESSTOKEN@organization.visualstudio.com/AzureDevopsProjectName/_git/AzureDevopsProjectName.wiki"
```

