#Requires -Version 5.1
<#
.SYNOPSIS
    Extracts public FCSA content from WordPress and builds a static HTML site.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$OutputRoot = '',
    [switch]$SkipMediaDownload,
    [switch]$SkipPageFetch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..\..')).Path
}

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $RepoRoot 'sites\fcsa\dist'
}

$assetsImages = Join-Path $OutputRoot 'assets\images'
$assetsDocs = Join-Path $OutputRoot 'assets\documents'
$docsDir = Join-Path $RepoRoot 'sites\fcsa\docs'
$cssSource = Join-Path $RepoRoot 'sites\fcsa\src\css\site.css'

New-Item -ItemType Directory -Force -Path $assetsImages, $assetsDocs, $docsDir | Out-Null
if (Test-Path $OutputRoot) {
    Get-ChildItem $OutputRoot -Exclude 'assets' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
}

$ExcludeSlugs = @(
    'log-in', 'register', 'edit-profile', 'dashboard', 'no-access',
    'connexion-du-membre', 'draft-landing-page-with-advanced-ads'
)

# WordPress slug -> relative site path (from site root)
$SlugToPath = @{
    'home' = 'index.html'
    'about' = 'about/index.html'
    'corporate-profile' = 'about/corporate-profile.html'
    'our-mandate' = 'about/mandate.html'
    'our-key-roles' = 'about/key-roles.html'
    'our-members' = 'members/index.html'
    'membership-benefits' = 'about/membership-benefits.html'
    'radio-frequency-interference-analysis-service' = 'about/rf-interference-service.html'
    'governance' = 'governance/index.html'
    'group-description' = 'governance/group-description.html'
    'officers' = 'governance/officers.html'
    'board-of-directors' = 'governance/board-of-directors.html'
    'committee-members' = 'governance/committee-members.html'
    'member-delegates' = 'governance/member-delegates.html'
    'working-group-chairpersons-members' = 'governance/working-groups.html'
    'resources' = 'resources/index.html'
    'events' = 'events/index.html'
    'contact-us' = 'contact/index.html'
    'become-a-member' = 'members/join.html'
    'apply' = 'members/apply.html'
    'privacy-policy' = 'privacy.html'
    'working-groups' = 'working-groups/index.html'
    'antenna-manufacturers' = 'members/antenna-manufacturers.html'
    'equipment-manufacturers' = 'members/equipment-manufacturers.html'
    'radio-frequency-ias' = 'members/radio-frequency-ias.html'
    'members-list' = 'members/list.html'
    'accueil' = 'fr/index.html'
    'a-propos-de-lapcf' = 'fr/about/index.html'
    'gouvernance' = 'fr/governance/index.html'
    'conseil-dadministration-de-lapcf' = 'fr/governance/board.html'
    'dirigeants-de-lapcf' = 'fr/governance/officers.html'
    'membres-delegues-de-lapcf' = 'fr/governance/delegates.html'
    'membres-du-comite' = 'fr/governance/committee.html'
    'presidents-et-membres-des-groupes-de-travail' = 'fr/governance/working-groups.html'
    'ressources' = 'fr/resources/index.html'
    'evenements' = 'fr/events/index.html'
    'pour-nous-joindre' = 'fr/contact/index.html'
    'demand-dadhesion' = 'fr/members/join.html'
    'politique-de-confidentialite' = 'fr/privacy.html'
    'services-danalyse-des-radiofrequences-a-micro-ondes' = 'fr/about/rf-service.html'
}

$LinkOverrides = @{
    'https://fcsa.ca/about/our-members/' = 'about/members.html'
}

$UrlPathMap = @{
    '/' = 'index.html'
    '/fr/accueil/' = 'fr/index.html'
    '/about/' = 'about/index.html'
    '/about/corporate-profile/' = 'about/corporate-profile.html'
    '/about/our-mandate/' = 'about/mandate.html'
    '/about/our-key-roles/' = 'about/key-roles.html'
    '/about/our-members/' = 'about/members.html'
    '/about/membership-benefits/' = 'about/membership-benefits.html'
    '/about/radio-frequency-interference-analysis-service/' = 'about/rf-interference-service.html'
    '/governance/' = 'governance/index.html'
    '/governance/group-description/' = 'governance/group-description.html'
    '/governance/officers/' = 'governance/officers.html'
    '/governance/board-of-directors/' = 'governance/board-of-directors.html'
    '/governance/committee-members/' = 'governance/committee-members.html'
    '/governance/member-delegates/' = 'governance/member-delegates.html'
    '/governance/working-group-chairpersons-members/' = 'governance/working-groups.html'
    '/resources/' = 'resources/index.html'
    '/events/' = 'events/index.html'
    '/contact-us/' = 'contact/index.html'
    '/become-a-member/' = 'members/join.html'
    '/apply/' = 'members/apply.html'
    '/privacy-policy/' = 'privacy.html'
    '/working-groups/' = 'working-groups/index.html'
    '/antenna-manufacturers/' = 'members/antenna-manufacturers.html'
    '/equipment-manufacturers/' = 'members/equipment-manufacturers.html'
    '/radio-frequency-ias/' = 'members/radio-frequency-ias.html'
    '/our-members/' = 'members/index.html'
    '/members-list/' = 'members/list.html'
    '/fr/a-propos-de-lapcf/' = 'fr/about/index.html'
    '/fr/gouvernance/' = 'fr/governance/index.html'
    '/fr/gouvernance/conseil-dadministration-de-lapcf/' = 'fr/governance/board.html'
    '/fr/gouvernance/dirigeants-de-lapcf/' = 'fr/governance/officers.html'
    '/fr/gouvernance/membres-delegues-de-lapcf/' = 'fr/governance/delegates.html'
    '/fr/gouvernance/membres-du-comite/' = 'fr/governance/committee.html'
    '/fr/presidents-et-membres-des-groupes-de-travail/' = 'fr/governance/working-groups.html'
    '/fr/ressources/' = 'fr/resources/index.html'
    '/fr/evenements/' = 'fr/events/index.html'
    '/fr/pour-nous-joindre/' = 'fr/contact/index.html'
    '/fr/demand-dadhesion/' = 'fr/members/join.html'
    '/fr/politique-de-confidentialite/' = 'fr/privacy.html'
    '/fr/services-danalyse-des-radiofrequences-a-micro-ondes/' = 'fr/about/rf-service.html'
}

function Get-RelativePathToRoot {
    param([string]$TargetPath)
    $parts = @($TargetPath -replace '\\', '/' -split '/' | Where-Object { $_ -and $_ -notmatch '\.html$' })
    $depth = $parts.Count
    if ($depth -le 0) { return '' }
    return ('../' * $depth)
}

function Get-PageContentFromHtml {
    param([string]$Html)
    $match = [regex]::Match($Html, '(?s)<div class="entry-content">(.*?)</div>\s*</article>')
    if (-not $match.Success) {
        $match = [regex]::Match($Html, '(?s)<article[^>]*id="post-\d+"[^>]*>(.*?)</article>')
    }
    if (-not $match.Success) { return '' }
    $content = $match.Groups[1].Value
    $content = [regex]::Replace($content, '(?s)<script.*?</script>', '')
    $content = [regex]::Replace($content, '(?s)<style.*?</style>', '')
    $content = [regex]::Replace($content, '(?s)<!--.*?-->', '')
    # Use plain img tags only — we mirror PNG/JPG originals, not WordPress WebP or srcset variants.
    $content = [regex]::Replace($content, '(?s)<source[^>]*>\s*', '')
    $content = [regex]::Replace($content, '\s+srcset="[^"]*"', '')
    $content = [regex]::Replace($content, '\s+sizes="[^"]*"', '')
    $content = [regex]::Replace($content, '<picture[^>]*>\s*', '')
    $content = [regex]::Replace($content, '\s*</picture>', '')
    return $content.Trim()
}

function Resolve-LocalImageName {
    param(
        [string]$FileName,
        [string[]]$AvailableNames
    )
    if ($FileName -in $AvailableNames) { return $FileName }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($FileName -match '\.webp$') {
        $candidates.Add($FileName -replace '\.webp$', '')
    }
    if ($FileName -match '^(.*)-(\d+)x(\d+)(\.[^.]+)$') {
        $candidates.Add($Matches[1] + $Matches[4])
    }
    if ($FileName -match '^(.*)-(\d+)x(\d+)\.webp$') {
        $candidates.Add($Matches[1] + '.png')
        $candidates.Add($Matches[1] + '.jpg')
        $candidates.Add($Matches[1] + '.jpeg')
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and ($candidate -in $AvailableNames)) {
            return $candidate
        }
    }
    return $FileName
}

function Ensure-LocalImages {
    param(
        [string]$Content,
        [string]$ImagesDir
    )
    if (-not (Test-Path $ImagesDir)) { return $Content }

    $available = @(Get-ChildItem $ImagesDir -File | Select-Object -ExpandProperty Name)

    $Content = [regex]::Replace($Content, 'src="([^"]*assets/images/([^"?#]+))"', {
        param($m)
        $prefixPath = $m.Groups[1].Value
        $fileName = $m.Groups[2].Value
        $resolved = Resolve-LocalImageName -FileName $fileName -AvailableNames $available
        if ($resolved -ne $fileName) {
            return ('src="' + ($prefixPath -replace [regex]::Escape($fileName), $resolved) + '"')
        }

        $localPath = Join-Path $ImagesDir $fileName
        if (-not (Test-Path $localPath)) {
            $wpUrl = "https://fcsa.ca/wp-content/uploads/2019/07/$fileName"
            try {
                & curl.exe -sL -o $localPath $wpUrl | Out-Null
                if ((Test-Path $localPath) -and (Get-Item $localPath).Length -gt 0) {
                    $header = Get-Content $localPath -Encoding Byte -TotalCount 5
                    $head = [System.Text.Encoding]::ASCII.GetString($header)
                    if ($head -notmatch '^<!DOC|<html') {
                        $available += $fileName
                        return $m.Value
                    }
                }
                Remove-Item $localPath -Force -ErrorAction SilentlyContinue
            } catch { }

            foreach ($year in @('2019/10', '2019/12', '2022/09', '2025/11')) {
                $wpUrl = "https://fcsa.ca/wp-content/uploads/$year/$fileName"
                try {
                    & curl.exe -sL -o $localPath $wpUrl | Out-Null
                    if ((Test-Path $localPath) -and (Get-Item $localPath).Length -gt 0) {
                        $header = Get-Content $localPath -Encoding Byte -TotalCount 5
                        $head = [System.Text.Encoding]::ASCII.GetString($header)
                        if ($head -notmatch '^<!DOC|<html') {
                            return $m.Value
                        }
                    }
                    Remove-Item $localPath -Force -ErrorAction SilentlyContinue
                } catch { }
            }

            $resolved = Resolve-LocalImageName -FileName $fileName -AvailableNames $available
            if ($resolved -ne $fileName) {
                return ('src="' + ($prefixPath -replace [regex]::Escape($fileName), $resolved) + '"')
            }
        }
        return $m.Value
    })

    return $Content
}

function Rewrite-ContentUrls {
    param(
        [string]$Content,
        [string]$PageRelPath
    )
    $prefix = Get-RelativePathToRoot -TargetPath $PageRelPath

    $Content = [regex]::Replace($Content, 'https?://fcsa\.ca/wp-content/uploads/([^"''>\s]+)', {
        param($m)
        $rel = $m.Groups[1].Value
        $fileName = Split-Path ($rel -replace '\\', '/') -Leaf
        if ($rel -match '\.(pdf|doc|docx)(\?|$)') {
            return ($prefix + "assets/documents/$fileName")
        }
        return ($prefix + "assets/images/$fileName")
    })

    $Content = [regex]::Replace($Content, '/wp-content/uploads/([^"''>\s]+)', {
        param($m)
        $rel = $m.Groups[1].Value
        $fileName = Split-Path ($rel -replace '\\', '/') -Leaf
        if ($rel -match '\.(pdf|doc|docx)(\?|$)') {
            return ($prefix + "assets/documents/$fileName")
        }
        return ($prefix + "assets/images/$fileName")
    })

    $sortedPaths = $UrlPathMap.Keys | Sort-Object { $_.Length } -Descending
    foreach ($wpPath in $sortedPaths) {
        $target = $UrlPathMap[$wpPath]
        $targetWithPrefix = $prefix + ($target -replace '\\', '/')
        if ($wpPath -eq '/') {
            $Content = [regex]::Replace($Content, 'https://fcsa\.ca/(?!wp-content)', $targetWithPrefix)
            $Content = [regex]::Replace($Content, 'href="/"', "href=`"$targetWithPrefix`"")
        } else {
            $escaped = [regex]::Escape("https://fcsa.ca$wpPath")
            $Content = [regex]::Replace($Content, $escaped, $targetWithPrefix)
            $Content = [regex]::Replace($Content, "href=`"$wpPath", "href=`"$targetWithPrefix")
        }
    }

    $Content = [regex]::Replace($Content, '(?s)<a[^>]+href="[^"]*(?:log-in|register|dashboard|edit-profile|no-access|connexion-du-membre)[^"]*"[^>]*>.*?</a>', '')
    return $Content
}

function Get-SiteHeader {
    param(
        [string]$PageRelPath,
        [ValidateSet('en', 'fr')]
        [string]$Lang = 'en'
    )
    $root = Get-RelativePathToRoot -TargetPath $PageRelPath
    $homeHref = "${root}index.html"
    $frHome = "${root}fr/index.html"
    $logo = "${root}assets/images/fcsa_white_logo.png"

    if ($Lang -eq 'fr') {
        $nav = @"
<nav class="site-nav" aria-label="Navigation principale">
  <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="primary-nav">Menu</button>
  <ul id="primary-nav" class="nav-list">
    <li><a href="$homeHref">English</a></li>
    <li><a href="${root}fr/index.html">Accueil</a></li>
    <li><a href="${root}fr/about/index.html">A propos</a></li>
    <li><a href="${root}fr/governance/index.html">Gouvernance</a></li>
    <li><a href="${root}fr/resources/index.html">Ressources</a></li>
    <li><a href="${root}fr/events/index.html">Evenements</a></li>
    <li><a href="${root}fr/members/join.html">Adhesion</a></li>
    <li><a href="${root}fr/contact/index.html">Contact</a></li>
  </ul>
</nav>
"@
        $langLink = "<a class=""lang-switch"" href=""$homeHref"">English</a>"
        $brandHref = "${root}fr/index.html"
    } else {
        $nav = @"
<nav class="site-nav" aria-label="Primary navigation">
  <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="primary-nav">Menu</button>
  <ul id="primary-nav" class="nav-list">
    <li><a href="$homeHref">Home</a></li>
    <li><a href="${root}about/index.html">About</a></li>
    <li><a href="${root}governance/index.html">Governance</a></li>
    <li><a href="${root}resources/index.html">Resources</a></li>
    <li><a href="${root}events/index.html">Events</a></li>
    <li><a href="${root}members/join.html">Membership</a></li>
    <li><a href="${root}working-groups/index.html">Working Groups</a></li>
    <li><a href="${root}contact/index.html">Contact</a></li>
  </ul>
</nav>
"@
        $langLink = "<a class=""lang-switch"" href=""$frHome"">Francais</a>"
        $brandHref = $homeHref
    }

    return @"
<header class="site-header">
  <div class="header-inner">
    <a class="brand" href="$brandHref">
      <img src="$logo" alt="FCSA" width="220" height="60" onerror="this.style.display='none';this.nextElementSibling.style.display='inline'">
      <span class="brand-text" style="display:none">FCSA</span>
    </a>
    $langLink
  </div>
  $nav
</header>
"@
}

function Get-SiteFooter {
    param(
        [string]$PageRelPath,
        [ValidateSet('en', 'fr')]
        [string]$Lang = 'en'
    )
    $root = Get-RelativePathToRoot -TargetPath $PageRelPath
    if ($Lang -eq 'fr') {
        return @"
<footer class="site-footer">
  <p>Association du systeme de coordination des frequences (APCF)</p>
  <p><a href="${root}fr/privacy.html">Politique de confidentialite</a></p>
</footer>
"@
    }
    return @"
<footer class="site-footer">
  <p>Frequency Coordination System Association (FCSA)</p>
  <p><a href="${root}privacy.html">Privacy Policy</a></p>
</footer>
"@
}

function Wrap-PageHtml {
    param(
        [string]$Title,
        [string]$BodyContent,
        [string]$PageRelPath,
        [ValidateSet('en', 'fr')]
        [string]$Lang = 'en'
    )
    $root = Get-RelativePathToRoot -TargetPath $PageRelPath
    $langAttr = if ($Lang -eq 'fr') { 'fr-CA' } else { 'en-CA' }
    $header = Get-SiteHeader -PageRelPath $PageRelPath -Lang $Lang
    $footer = Get-SiteFooter -PageRelPath $PageRelPath -Lang $Lang

    return @"
<!DOCTYPE html>
<html lang="$langAttr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$Title | FCSA</title>
  <link rel="stylesheet" href="${root}css/site.css">
</head>
<body>
  $header
  <main class="site-main content-from-wp">
    $BodyContent
  </main>
  $footer
  <script src="${root}js/site.js"></script>
</body>
</html>
"@
}

Write-Host 'Fetching WordPress page list...'
$allPages = Invoke-RestMethod -Uri 'https://fcsa.ca/wp-json/wp/v2/pages?per_page=100' -TimeoutSec 120
$pages = $allPages | Where-Object { $_.slug -notin $ExcludeSlugs }
Write-Host "Pages to build: $($pages.Count)"

Write-Host 'Downloading media...'
$mediaItems = Invoke-RestMethod -Uri 'https://fcsa.ca/wp-json/wp/v2/media?per_page=100' -TimeoutSec 120
$assetManifest = @()

if (-not $SkipMediaDownload) {
    foreach ($item in $mediaItems) {
        $url = $item.source_url
        $fileName = Split-Path ([uri]$url).LocalPath -Leaf
        $isDoc = $item.mime_type -match 'pdf|document|msword'
        $destDir = if ($isDoc) { $assetsDocs } else { $assetsImages }
        $destPath = Join-Path $destDir $fileName
        if (-not (Test-Path $destPath)) {
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
                $wc.DownloadFile($url, $destPath)
                Write-Host "  Downloaded $fileName"
            } catch {
                try {
                    $encodedUrl = [uri]::EscapeUriString($url)
                    & curl.exe -sL -o $destPath $encodedUrl
                    if ((Test-Path $destPath) -and (Get-Item $destPath).Length -gt 0) {
                        Write-Host "  Downloaded $fileName (curl)"
                    } else {
                        throw 'curl returned empty file'
                    }
                } catch {
                    Write-Warning "  Failed: $url - $_"
                }
            }
        }
        $localRel = if ($isDoc) { "assets/documents/$fileName" } else { "assets/images/$fileName" }
        $assetManifest += [pscustomobject]@{
            id = $item.id
            slug = $item.slug
            source_url = $url
            local_path = $localRel
            mime_type = $item.mime_type
        }
    }
}

$cssDest = Join-Path $OutputRoot 'css'
$jsDest = Join-Path $OutputRoot 'js'
New-Item -ItemType Directory -Force -Path $cssDest, $jsDest | Out-Null
Copy-Item $cssSource (Join-Path $cssDest 'site.css') -Force
Copy-Item (Join-Path $RepoRoot 'sites\fcsa\src\js\site.js') (Join-Path $jsDest 'site.js') -Force

$urlMapRows = @()
$built = 0

foreach ($page in $pages) {
    $link = $page.link.TrimEnd('/') + '/'
    if ($LinkOverrides.ContainsKey($link)) {
        $relPath = $LinkOverrides[$link]
    } elseif ($SlugToPath.ContainsKey($page.slug)) {
        $relPath = $SlugToPath[$page.slug]
    } else {
        Write-Warning "No path mapping for slug $($page.slug) ($link) - skipping"
        continue
    }

    $lang = if ($relPath -like 'fr/*' -or $relPath -eq 'fr/index.html') { 'fr' } else { 'en' }
    $title = ($page.title.rendered -replace '<[^>]+>', '').Trim()
    if (-not $title) { $title = $page.slug }

    $outFile = Join-Path $OutputRoot ($relPath -replace '/', '\')
    $outDir = Split-Path $outFile -Parent
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $bodyContent = ''
    if (-not $SkipPageFetch) {
        try {
            $resp = Invoke-WebRequest -Uri $page.link -UseBasicParsing -TimeoutSec 120
            $raw = Get-PageContentFromHtml -Html $resp.Content
            $bodyContent = Rewrite-ContentUrls -Content $raw -PageRelPath $relPath
            $bodyContent = Ensure-LocalImages -Content $bodyContent -ImagesDir $assetsImages
        } catch {
            Write-Warning "Fetch failed for $($page.link): $_"
            $bodyContent = "<p>Content could not be retrieved. Title: $title</p>"
        }
    } else {
        $bodyContent = "<p>$title</p>"
    }

    $html = Wrap-PageHtml -Title $title -BodyContent $bodyContent -PageRelPath $relPath -Lang $lang
    [System.IO.File]::WriteAllText($outFile, $html, [System.Text.UTF8Encoding]::new($false))
    $built++

    $urlMapRows += [pscustomobject]@{
        wp_slug = $page.slug
        wp_url = $page.link
        new_path = '/' + ($relPath -replace '\\', '/')
        lang = $lang
    }
    Write-Host "Built $relPath"
}

$urlMapPath = Join-Path $docsDir 'fcsa-url-map.csv'
$urlMapRows | Export-Csv -Path $urlMapPath -NoTypeInformation -Encoding UTF8

$manifestPath = Join-Path $docsDir 'assets-manifest.csv'
$assetManifest | Export-Csv -Path $manifestPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Done. Built $built pages to $OutputRoot"
Write-Host "URL map: $urlMapPath"
Write-Host "Assets: $($assetManifest.Count) items"
