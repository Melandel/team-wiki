<#
	Takes a file as a parameter
	Browses the file and all the markdown files matching any parent directory
	Generates a listing of the children and grandchildren for browsed files that are either empty, either contain the two markers <!-- Listing --> and <!-- -->

	How to use
	cd to the git repository root folder
	(Get-ChildItem -Recurse -Filter *.order -Path .\TEAM-WIKI-PAGE\) | % {. .\.scripts\Build-MarkdownListingSectionFromRecursiveChildrenPages.ps1 (Resolve-Path -LiteralPath $_.FullName -Relative)}

	I tried running the script on all the .order files inside SourceHub wiki. It took about 90 seconds to complete.

	The script above finds all .order files inside the team wiki and calls this script on each of them
	Which should end up re-generating all files inside the subwiki at least once)

	DISCLAIMER: Just like any powershell script I write, this is shameful, unspeakable and made-in-pain-and-agony-up-until-2-AM-over-several-days code from a dev that just wanted things to be functional asap
	You might actually go to hell if you share it without cleaning it up beforehand.
	You are warned!
#>

param(
	[string]$mdFileRelativePath
)

function Get-ParentFilePathsToModify {
	param ( [string]$mdFileRelativePath )
 $parents = @()
	$remaining = $mdFileRelativePath
	$separator = [IO.Path]::DirectorySeparatorChar
	while ($remaining.Contains($separator)) {
		$parent = Split-Path $remaining -Parent
		if (-Not($parent -eq '.')) {
		# Disgusting hack for files with bracket characters.
		# Why is Powershell always so annoying?
		# Without -LiteralPath, we get an error because the file (with brackets escaped with backticks) is not found
		# With -LiteralPath, we threat the file as though it actually had backticks in its name
		# I am so done with this sh**
			$parents += ($parent.Replace('`', '') + '.md')
		}
		$remaining =  $parent
	}
	$parents | Where { (Select-String -LiteralPath "$_" -Pattern "^<!-- Listing -->$" -Quiet) -or ((Get-Content -LiteralPath $_).Length -eq 0) }
}

function Get-FileContentWithOverridedListingCommentBlock {
	param ( [string]$mdFileRelativePath )
	$lines = Get-Content -LiteralPath $mdFileRelativePath -Encoding UTF8
	$new = @()
	$skipNextLine = $false
	if ($lines.Count -eq 0) {
		$lines = @("<!-- Listing -->", "<!-- -->")
	}

	foreach ( $line in $lines ) {
		if ($line -eq "<!-- -->") {
			$skipNextLine = $false
			$folderRelativePath = Remove-MarkdownExtension $mdFileRelativePath
			#$new += Build-MarkdownTextForListingOfRecursiveChildPages $folderRelativePath
			$new += Build-MarkdownTextForListingOfChildrenAndGrandChildrenPages $folderRelativePath
		}
		if ($skipNextLine){
			continue
		}
		$new += $line
		if ($line -eq "<!-- Listing -->") {
			$skipNextLine = $true
		}
	}
	$new
}

function Build-MarkdownTextForListingOfChildrenAndGrandChildrenPages {
	param( [string]$folderRelativePath)
	$hyperlinkLines = New-Object System.Collections.Generic.List[System.String]

	$childLeafPages = Get-ChildLeafPages $folderRelativePath
	foreach ( $childLeafPage in $childLeafPages ) {
		[void] $hyperlinkLines.Add("### $(Get-MarkdownHyperLinkWithItalicTitle $childLeafPage)")
	}

	$childPagesWithChildren = Get-ChildPagesWithChildren $folderRelativePath
	foreach ( $childPageWithChildren in $childPagesWithChildren ) {
		[void] $hyperlinkLines.Add("### $(Get-MarkdownHyperLink $childPageWithChildren)")

		$allChildrenPagesWithoutExtension = Get-ChildPagesWithoutExtension $childPageWithChildren
		foreach ( $childPageWithoutExtension in $allChildrenPagesWithoutExtension ) {
			$hasChildrenPages = (Test-Path -LiteralPath $childPageWithoutExtension)
			if ( $hasChildrenPages ) {
				[void] $hyperlinkLines.Add("* $(Get-MarkdownHyperLink $childPageWithoutExtension)")
			} else {
				[void] $hyperlinkLines.Add("* $(Get-MarkdownHyperLinkWithItalicTitle $childPageWithoutExtension)")
			}
		}

	}

	$builder = [System.Text.StringBuilder]::new()
	if ($hyperlinkLines.Count -gt 0) {
		[void] $builder.AppendLine("<!-- The following was automatically generated. -->")
		[void] $builder.AppendLine("&nbsp;")
		[void] $builder.AppendLine("## $scrollEmoji Listing $scrollEmoji")
		$hasOnlyLeafChildren = (($hyperlinkLines -Match '^### \[[^_]').Count -eq 0)
		foreach ( $hyperlinkLine in $hyperlinkLines ) {
			if ($hasOnlyLeafChildren) {
				[void] $builder.AppendLine("* $hyperlinkLine")
			} else {
				[void] $builder.AppendLine($hyperlinkLine)
			}
		}
		$builder.Length -= ([Environment]::NewLine).Length
	}
	$builder.ToString()
}

function Build-MarkdownTextForListingOfRecursiveChildPages {
	param( [string]$folderRelativePath)

	$builder = [System.Text.StringBuilder]::new()
	[void] $builder.AppendLine("<!-- The following was automatically generated. -->")
	[void] $builder.AppendLine("&nbsp;")
	$folderRelativePath = ($folderRelativePath | Resolve-Path -Relative -LiteralPath {$_})
	$currentWikiPath = "/$(Overwrite-BackwardsSlashWithForwardSlashInPath $folderRelativePath.TrimStart(".\"))"
	Iterate-RecursiveFunction $builder $folderRelativePath $currentWikiPath $defaultHeaderLevel
	$builder.Length -= ([Environment]::NewLine).Length
	$builder.ToString()
}

function Iterate-RecursiveFunction {
	param ( [System.Text.StringBuilder] $builder, [string] $folderRelativePath, [string] $currentWikiPath, [int] $headerLevel)
	if ($headerLevel -gt $maxHeaderLevel) {
		return
	}

	$folderName = ($folderRelativePath | Split-Path -Leaf)
	$header = "$("#" * $headerLevel) $(If ($headerLevel -eq $defaultHeaderLevel) { "$scrollEmoji Listing $scrollEmoji" } Else { "[$(Decode-WikiTitle $folderName)]($currentWikiPath)" })"
	[void]$builder.AppendLine($header)


	$wikiFilePaths = Get-Content -LiteralPath (Join-Path $folderRelativePath ".order") -Encoding UTF8 | Where { -Not (Test-Path -LiteralPath (Join-Path $folderRelativePath $_))}

	$wikiPages = $wikiFilePaths |
		Select @{Label = 'Path'; Expression =  {"$currentWikiPath/$(Overwrite-BackwardsSlashWithForwardSlashInPath $_)"}},@{Label = 'Title'; Expression =  {(Decode-WikiTitle $_)}}

	if ($headerLevel -lt $maxHeaderLevel) {
		$wikiPagesAsBulletPoints = $($($wikiPages | Select @{Label = 'Markdown'; Expression = {"* [$($_.Title)]($($_.Path))"}} | Select -ExpandProperty Markdown) -join "`r`n")
		if ($wikiPagesAsBulletPoints.Length -gt 0) {
			[void]$builder.AppendLine($wikiPagesAsBulletPoints)
		}

		$subfolderPaths = (Get-ChildItem -Directory -LiteralPath $folderRelativePath | Resolve-Path -Relative)

		if ($subfolderPaths.Count -gt 0) {
			$catalogSubfolderPaths = $subfolderPaths | Where {$_.Contains("CATALOG-OF")}
			if ($catalogSubfolderPaths.Count -gt 0) {
				foreach ( $DirectoryName in $catalogSubfolderPaths ) {
					$dirName = (Split-Path $DirectoryName -Leaf)
					$dirTitle = (Decode-WikiTitle $dirName)
					$dirTitle = $dirTitle.Substring(0,1).ToUpper() + $dirTitle.Substring(1).ToLower()
					$header = "* $("[$dirTitle]($currentWikiPath/$dirName)")"
					[void]$builder.AppendLine($header)
				}
			}

			$nonCatalogSubfolderPaths = $subfolderPaths | Where {-Not $_.Contains("CATALOG-OF")}
			if (($nonCatalogSubfolderPaths.Count -gt 0)) {
				foreach ( $DirectoryName in $nonCatalogSubfolderPaths ) {
					Iterate-RecursiveFunction $builder $DirectoryName "$currentWikiPath/$($DirectoryName | Split-Path -Leaf)" ($headerLevel+1)
				}
			}
		}
	}
}

function overwrite-backwardsslashwithforwardslashinpath {
	param ( [string]$path )
 $tokens = @()
	$remaining = $path
	$tokens += Split-Path $remaining -Leaf
	$separator = [IO.Path]::DirectorySeparatorChar
	while ($remaining.Contains($separator)) {
		$parentPath = Split-Path $remaining -Parent
		$parentName = Split-Path ($parentPath) -Leaf
		if (-Not($parentPath -eq '.')) {
			$tokens = @($parentName) + $tokens
		}
		$remaining =  $parentPath
	}
	$forwardSlashedPath = $tokens -Join "/"
	$forwardSlashedPath
}

function Encode-WikiTitle {
	param ([string] $title)
	$title.Replace("'", '%22').Replace('-', '%2D').Replace('<', '%3C').Replace('>', '%3E').Replace(':', '%3A').Replace('?', '%3F').Replace('|', '%7C').Replace(' ', '-')
}

function Decode-WikiTitle {
	param ([string] $title)
	$title.Replace("-", " ").Replace("%22", "'").Replace('%2D', '-').Replace('%3C', '<').Replace('%3E', '>').Replace('%3A', ':').Replace('%3F', '?').Replace('%7C', '|')
}

function Remove-MarkdownExtension {
	param ([string] $mdFilePath)
	$mdFilePath.Substring(0, $mdFilePath.Length - '.md'.Length)
}

function Add-MarkdownExtension {
	param ([string] $mdFilePath)
	"$mdFilePath.md"
}

function Get-ChildPagesWithoutExtension {
	param ([string] $folderRelativePath)

	Get-Content -LiteralPath (Join-Path $folderRelativePath ".order") -Encoding UTF8 | % { Join-Path $folderRelativePath $_}
}

function Get-ChildLeafPages {
	param ([string] $folderRelativePath)

	Get-Content -LiteralPath (Join-Path $folderRelativePath ".order") -Encoding UTF8 | Where { -Not (Test-Path -LiteralPath (Join-Path $folderRelativePath $_))} | % { Join-Path $folderRelativePath $_}
}

function Get-ChildPagesWithChildren {
	param ([string] $folderRelativePath)

	Get-Content -LiteralPath (Join-Path $folderRelativePath ".order") -Encoding UTF8 | Where { Test-Path -LiteralPath (Join-Path $folderRelativePath $_) } | % { Join-Path $folderRelativePath $_}
}

function Get-MarkdownHyperLink {
	param ([string] $wikiPageFilePathWithoutExt)
	"[$(Get-WikiTitle $wikiPageFilePathWithoutExt)]($(Get-WikiPath $wikiPageFilePathWithoutExt))"
}

function Get-MarkdownHyperLinkWithItalicTitle {
	param ([string] $wikiPageFilePathWithoutExt)
	"[_$(Get-WikiTitle $wikiPageFilePathWithoutExt)_]($(Get-WikiPath $wikiPageFilePathWithoutExt))"
}

function Get-WikiTitle {
	param ([string] $wikiPageFilePathWithoutExt)

	$filename = Split-Path $wikiPageFilePathWithoutExt -Leaf
	$title = Decode-WikiTitle $filename
	$title
}

function Get-WikiPath {
	param ([string] $wikiPageFilePathWithoutExt)

	$forwardSlashedPath = Overwrite-BackwardsSlashWithForwardSlashInPath $wikiPageFilePathWithoutExt
	$path = "/$($forwardSlashedPath.TrimStart('.\'))"
	$path
}

# Entry Point
$scrollEmoji = [System.Char]::ConvertFromUtf32([System.Convert]::toInt32("1F4DC",16))
$pathsToModify = Get-ParentFilePathsToModify $mdFileRelativePath
foreach ( $filePath in $pathsToModify ) {
	#echo "filePath $filePath"; Get-FileContentWithOverridedListingCommentBlock $filePath
	Set-Content -LiteralPath $filePath (Get-FileContentWithOverridedListingCommentBlock $filePath) -Encoding UTF8
}
