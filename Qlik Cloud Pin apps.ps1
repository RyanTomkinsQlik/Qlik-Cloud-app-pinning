# =============================================================================
# Qlik Cloud - Pin App to Engine Size
# API Reference: https://qlik.dev/manage/analytics-applications/analytics-engine-size-override/
# Apps API:      https://qlik.dev/apis/rest/items/
#
# Prerequisites:
#   - App must be in a space with Large Apps support enabled
#   - API key for a user with Tenant Admin, Analytics Admin, or a custom role
#     that includes the "Manage engine assignments for applications" (apps:manage) scope
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =============================================================================
# CONFIGURATION - Optionally pre-fill these to skip typing in the form
# =============================================================================
$global:QlikTenantUrl = ""   # e.g. "https://your-tenant.us.qlikcloud.com"
$global:QlikApiKey    = ""   # Your Qlik Cloud API key

# Valid engine sizes per Qlik documentation
$global:EngineSizes = [ordered]@{
    "No Override - Automatic Placement  (0)"   = "0"
    "40 GB  pod or larger              (40)"   = "40"
    "60 GB  pod or larger              (60)"   = "60"
    "80 GB  pod or larger              (80)"   = "80"
    "120 GB pod or larger             (120)"   = "120"
    "160 GB pod or larger             (160)"   = "160"
    "200 GB pod or larger             (200)"   = "200"
}

# =============================================================================
# HELPER: Invoke Qlik Cloud REST API (PS 5.1 compatible)
# =============================================================================
function Invoke-QlikAPI {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Body = $null
    )

    $uri = "$($global:QlikTenantUrl.TrimEnd('/'))$Path"
    $headers = @{
        "Authorization" = "Bearer $global:QlikApiKey"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }

    $params = @{
        Method  = $Method
        Uri     = $uri
        Headers = $headers
    }

    if ($Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
    }

    try {
        $response = Invoke-RestMethod @params -ErrorAction Stop
        return $response
    }
    catch {
        $errMsg = $_.Exception.Message
        try {
            $httpResp = $_.Exception.Response
            if ($httpResp) {
                $statusCode = [int]$httpResp.StatusCode
                $stream = $httpResp.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $body   = $reader.ReadToEnd()
                $reader.Close()
                $errMsg = "HTTP $statusCode ($($httpResp.StatusCode))"
                if ($body) { $errMsg += "`n`n$body" }
            }
        }
        catch { }
        throw $errMsg
    }
}

# =============================================================================
# HELPER: Get all apps via /api/v1/items?resourceType=app (handles pagination)
# =============================================================================
function Get-AllQlikApps {
    $allApps   = [System.Collections.Generic.List[object]]::new()
    $nextToken = $null

    do {
        $url = "/api/v1/items?resourceType=app&limit=100&sort=%2Bname"
        if ($nextToken) { $url += "&next=$nextToken" }

        $result = Invoke-QlikAPI -Method GET -Path $url
        if ($result.data) {
            foreach ($item in $result.data) { $allApps.Add($item) }
        }
        $nextToken = $result.next
    } while ($nextToken)

    return $allApps
}

# =============================================================================
# HELPER: Get current placement for an app
# Returns object with .minEngineSize, or $null if no override set
# =============================================================================
function Get-AppPlacement {
    param([string]$AppId)
    try {
        $result = Invoke-QlikAPI -Method GET -Path "/api/v1/apps/$AppId/placement"
        return $result
    }
    catch {
        if ($_ -match "404") { return $null }
        throw
    }
}

# =============================================================================
# HELPER: Pin / unpin app engine size
# =============================================================================
function Set-AppPlacement {
    param(
        [string]$AppId,
        [string]$MinEngineSize
    )

    if ($MinEngineSize -eq "0") {
        try {
            Invoke-QlikAPI -Method DELETE -Path "/api/v1/apps/$AppId/placement"
        }
        catch {
            if ($_ -match "404") { return }
            throw
        }
    }
    else {
        $body = @{ minEngineSize = $MinEngineSize }
        Invoke-QlikAPI -Method PUT -Path "/api/v1/apps/$AppId/placement" -Body $body
    }
}

# =============================================================================
# SHARED: Update the placement panel for a given AppId
# =============================================================================
function Update-PlacementPanel {
    param(
        [string]$AppId,
        $Panel,
        $Label
    )

    $Label.Text      = "Checking..."
        $Label.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $Panel.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 255)
    $Panel.Refresh()

    try {
        $placement = Get-AppPlacement -AppId $AppId
        if ($placement -and $placement.minEngineSize -and $placement.minEngineSize -ne "0") {
            $Label.Text      = "Current engine pin:  $($placement.minEngineSize) GB  (manually pinned)"
            $Label.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 175)
            $Panel.BackColor = [System.Drawing.Color]::FromArgb(220, 235, 255)
        }
        else {
            $Label.Text      = "Current engine pin:  None  (automatic placement)"
            $Label.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
            $Panel.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
        }
    }
    catch {
        $Label.Text      = "Could not retrieve placement: $_"
        $Label.ForeColor = [System.Drawing.Color]::DarkRed
        $Panel.BackColor = [System.Drawing.Color]::FromArgb(255, 230, 230)
    }
}

# =============================================================================
# BUILD THE WINDOWS FORM
# =============================================================================
function Show-QlikPinForm {

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Qlik Cloud - Pin App to Engine Size"
    $form.Size            = New-Object System.Drawing.Size(580, 510)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.BackColor       = [System.Drawing.Color]::FromArgb(245, 245, 248)
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    # ---- Banner -------------------------------------------------------------
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Size      = New-Object System.Drawing.Size(580, 56)
    $banner.Location  = New-Object System.Drawing.Point(0, 0)
    $banner.BackColor = [System.Drawing.Color]::FromArgb(0, 100, 175)
    $form.Controls.Add($banner)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "  Pin App to Engine Size"
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Size      = New-Object System.Drawing.Size(560, 56)
    $lblTitle.Location  = New-Object System.Drawing.Point(0, 0)
    $lblTitle.TextAlign = "MiddleLeft"
    $banner.Controls.Add($lblTitle)

    # ---- Connection group ---------------------------------------------------
    $grpConn = New-Object System.Windows.Forms.GroupBox
    $grpConn.Text     = "Tenant Connection"
    $grpConn.Size     = New-Object System.Drawing.Size(536, 95)
    $grpConn.Location = New-Object System.Drawing.Point(20, 70)
    $form.Controls.Add($grpConn)

    $lblUrl = New-Object System.Windows.Forms.Label
    $lblUrl.Text     = "Tenant URL:"
    $lblUrl.Location = New-Object System.Drawing.Point(10, 26)
    $lblUrl.Size     = New-Object System.Drawing.Size(80, 20)
    $grpConn.Controls.Add($lblUrl)

    $txtUrl = New-Object System.Windows.Forms.TextBox
    $txtUrl.Location = New-Object System.Drawing.Point(95, 23)
    $txtUrl.Size     = New-Object System.Drawing.Size(320, 22)
    $txtUrl.Text     = $global:QlikTenantUrl
    $grpConn.Controls.Add($txtUrl)

    $lblKey = New-Object System.Windows.Forms.Label
    $lblKey.Text     = "API Key:"
    $lblKey.Location = New-Object System.Drawing.Point(10, 58)
    $lblKey.Size     = New-Object System.Drawing.Size(80, 20)
    $grpConn.Controls.Add($lblKey)

    $txtKey = New-Object System.Windows.Forms.TextBox
    $txtKey.Location     = New-Object System.Drawing.Point(95, 55)
    $txtKey.Size         = New-Object System.Drawing.Size(320, 22)
    $txtKey.PasswordChar = '*'
    $txtKey.Text         = $global:QlikApiKey
    $grpConn.Controls.Add($txtKey)

    $btnLoad = New-Object System.Windows.Forms.Button
    $btnLoad.Text      = "Load Apps"
    $btnLoad.Location  = New-Object System.Drawing.Point(425, 36)
    $btnLoad.Size      = New-Object System.Drawing.Size(100, 34)
    $btnLoad.BackColor = [System.Drawing.Color]::FromArgb(0, 100, 175)
    $btnLoad.ForeColor = [System.Drawing.Color]::White
    $btnLoad.FlatStyle = "Flat"
    $btnLoad.FlatAppearance.BorderSize = 0
    $grpConn.Controls.Add($btnLoad)

    # ---- App selection group ------------------------------------------------
    # Dropdown is narrowed to leave room for the Check Pin button
    $grpApp = New-Object System.Windows.Forms.GroupBox
    $grpApp.Text     = "1. Select Application"
    $grpApp.Size     = New-Object System.Drawing.Size(536, 64)
    $grpApp.Location = New-Object System.Drawing.Point(20, 178)
    $form.Controls.Add($grpApp)

    $cmbApp = New-Object System.Windows.Forms.ComboBox
    $cmbApp.Location      = New-Object System.Drawing.Point(10, 26)
    $cmbApp.Size          = New-Object System.Drawing.Size(400, 24)
    $cmbApp.DropDownStyle = "DropDownList"
    $cmbApp.DisplayMember = "Display"
    $cmbApp.ValueMember   = "ResourceId"
    $grpApp.Controls.Add($cmbApp)

    $btnCheckPin = New-Object System.Windows.Forms.Button
    $btnCheckPin.Text      = "Check Pin"
    $btnCheckPin.Location  = New-Object System.Drawing.Point(418, 24)
    $btnCheckPin.Size      = New-Object System.Drawing.Size(106, 26)
    $btnCheckPin.BackColor = [System.Drawing.Color]::FromArgb(90, 90, 110)
    $btnCheckPin.ForeColor = [System.Drawing.Color]::White
    $btnCheckPin.FlatStyle = "Flat"
    $btnCheckPin.FlatAppearance.BorderSize = 0
    $btnCheckPin.Enabled   = $false
    $grpApp.Controls.Add($btnCheckPin)

    # ---- Current placement panel (visible coloured box) ---------------------
    $pnlPlacement = New-Object System.Windows.Forms.Panel
    $pnlPlacement.Size      = New-Object System.Drawing.Size(536, 36)
    $pnlPlacement.Location  = New-Object System.Drawing.Point(20, 252)
    $pnlPlacement.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
    $pnlPlacement.BorderStyle = "FixedSingle"
    $form.Controls.Add($pnlPlacement)

    $lblCurrentPlacement = New-Object System.Windows.Forms.Label
    $lblCurrentPlacement.Text      = "  Select an app and click Check Pin to see its current engine assignment."
    $lblCurrentPlacement.Location  = New-Object System.Drawing.Point(4, 0)
    $lblCurrentPlacement.Size      = New-Object System.Drawing.Size(526, 34)
    $lblCurrentPlacement.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $lblCurrentPlacement.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblCurrentPlacement.TextAlign = "MiddleLeft"
    $pnlPlacement.Controls.Add($lblCurrentPlacement)

    # ---- Engine size group --------------------------------------------------
    $grpEngine = New-Object System.Windows.Forms.GroupBox
    $grpEngine.Text     = "2. Select Engine Size to Apply"
    $grpEngine.Size     = New-Object System.Drawing.Size(536, 64)
    $grpEngine.Location = New-Object System.Drawing.Point(20, 300)
    $form.Controls.Add($grpEngine)

    $cmbEngine = New-Object System.Windows.Forms.ComboBox
    $cmbEngine.Location      = New-Object System.Drawing.Point(10, 26)
    $cmbEngine.Size          = New-Object System.Drawing.Size(514, 24)
    $cmbEngine.DropDownStyle = "DropDownList"
    $grpEngine.Controls.Add($cmbEngine)

    foreach ($label in $global:EngineSizes.Keys) {
        $cmbEngine.Items.Add($label) | Out-Null
    }
    $cmbEngine.SelectedIndex = 0

    # ---- Pin button ---------------------------------------------------------
    $btnPin = New-Object System.Windows.Forms.Button
    $btnPin.Text      = "Apply Engine Pin"
    $btnPin.Location  = New-Object System.Drawing.Point(20, 380)
    $btnPin.Size      = New-Object System.Drawing.Size(536, 42)
    $btnPin.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 80)
    $btnPin.ForeColor = [System.Drawing.Color]::White
    $btnPin.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnPin.FlatStyle = "Flat"
    $btnPin.FlatAppearance.BorderSize = 0
    $btnPin.Enabled   = $false
    $form.Controls.Add($btnPin)

    # ---- Status bar ---------------------------------------------------------
    $statusBar   = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = "Enter your tenant URL and API key, then click Load Apps."
    $statusBar.Items.Add($statusLabel) | Out-Null
    $form.Controls.Add($statusBar)

    # ==========================================================================
    # EVENT: Check Pin button - explicitly fetch and display current placement
    # ==========================================================================
    $btnCheckPin.Add_Click({
        if ($cmbApp.SelectedItem -eq $null) { return }
        $selectedApp = $cmbApp.SelectedItem
        $statusLabel.Text  = "Checking engine pin for '$($selectedApp.Name)'..."
        $form.Cursor       = [System.Windows.Forms.Cursors]::WaitCursor
        $btnCheckPin.Enabled = $false
        $form.Refresh()

        Update-PlacementPanel -AppId $selectedApp.ResourceId -Panel $pnlPlacement -Label $lblCurrentPlacement

        $statusLabel.Text    = "Engine pin check complete for '$($selectedApp.Name)'."
        $form.Cursor         = [System.Windows.Forms.Cursors]::Default
        $btnCheckPin.Enabled = $true
    })

    # ==========================================================================
    # EVENT: App dropdown changed - auto-refresh placement panel
    # ==========================================================================
    $cmbApp.Add_SelectedIndexChanged({
        if ($cmbApp.SelectedItem -eq $null) {
            $lblCurrentPlacement.Text      = "  Select an app and click Check Pin to see its current engine assignment."
            $lblCurrentPlacement.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
            $pnlPlacement.BackColor        = [System.Drawing.Color]::FromArgb(235, 235, 235)
            return
        }
        $selectedApp = $cmbApp.SelectedItem
        Update-PlacementPanel -AppId $selectedApp.ResourceId -Panel $pnlPlacement -Label $lblCurrentPlacement
    })

    # ==========================================================================
    # EVENT: Load Apps
    # ==========================================================================
    $btnLoad.Add_Click({
        $global:QlikTenantUrl = $txtUrl.Text.Trim()
        $global:QlikApiKey    = $txtKey.Text.Trim()

        if (-not $global:QlikTenantUrl -or -not $global:QlikApiKey) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please enter both the Tenant URL and API Key.",
                "Missing Input", "OK", "Warning") | Out-Null
            return
        }

        $statusLabel.Text    = "Connecting and fetching apps..."
        $form.Cursor         = [System.Windows.Forms.Cursors]::WaitCursor
        $btnLoad.Enabled     = $false
        $cmbApp.Items.Clear()
        $btnPin.Enabled      = $false
        $btnCheckPin.Enabled = $false
        $lblCurrentPlacement.Text      = "  Select an app and click Check Pin to see its current engine assignment."
        $lblCurrentPlacement.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
        $pnlPlacement.BackColor        = [System.Drawing.Color]::FromArgb(235, 235, 235)
        $form.Refresh()

        try {
            $apps = Get-AllQlikApps

            if ($apps.Count -eq 0) {
                $statusLabel.Text = "No apps found in this tenant."
                [System.Windows.Forms.MessageBox]::Show(
                    "No apps were found.", "No Apps", "OK", "Information") | Out-Null
            }
            else {
                foreach ($app in $apps) {
                    $item = [PSCustomObject]@{
                        Display    = "$($app.name)  [$($app.resourceId)]"
                        ResourceId = $app.resourceId
                        Name       = $app.name
                    }
                    $cmbApp.Items.Add($item) | Out-Null
                }
                $cmbApp.SelectedIndex = 0
                $btnPin.Enabled       = $true
                $btnCheckPin.Enabled  = $true
                $statusLabel.Text     = "Loaded $($apps.Count) app(s). Select an app and engine size, then click Apply."
            }
        }
        catch {
            $statusLabel.Text = "Error loading apps."
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to connect or retrieve apps:`n`n$_",
                "Connection Error", "OK", "Error") | Out-Null
        }
        finally {
            $form.Cursor     = [System.Windows.Forms.Cursors]::Default
            $btnLoad.Enabled = $true
        }
    })

    # ==========================================================================
    # EVENT: Apply Pin
    # ==========================================================================
    $btnPin.Add_Click({
        if ($cmbApp.SelectedItem -eq $null) {
            [System.Windows.Forms.MessageBox]::Show("Please select an app.", "No App Selected", "OK", "Warning") | Out-Null
            return
        }
        if ($cmbEngine.SelectedItem -eq $null) {
            [System.Windows.Forms.MessageBox]::Show("Please select an engine size.", "No Engine Selected", "OK", "Warning") | Out-Null
            return
        }

        $selectedApp   = $cmbApp.SelectedItem
        $selectedLabel = $cmbEngine.SelectedItem.ToString()
        $selectedSize  = $global:EngineSizes[$selectedLabel]

        $actionDesc = if ($selectedSize -eq "0") {
            "remove the engine pin (return to automatic placement)"
        } else {
            "pin it to a minimum $selectedSize GB engine"
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Apply the following change?`n`n" +
            "App  : $($selectedApp.Name)`n" +
            "ID   : $($selectedApp.ResourceId)`n" +
            "Size : $selectedLabel`n`n" +
            "This will $actionDesc.",
            "Confirm", "YesNo", "Question")

        if ($confirm -ne "Yes") { return }

        $statusLabel.Text = "Applying engine pin for '$($selectedApp.Name)'..."
        $form.Cursor      = [System.Windows.Forms.Cursors]::WaitCursor
        $btnPin.Enabled   = $false
        $form.Refresh()

        try {
            Set-AppPlacement -AppId $selectedApp.ResourceId -MinEngineSize $selectedSize

            # Refresh the placement panel to confirm the new state
            Update-PlacementPanel -AppId $selectedApp.ResourceId -Panel $pnlPlacement -Label $lblCurrentPlacement

            $statusLabel.Text = "Successfully applied engine pin for '$($selectedApp.Name)'."
            [System.Windows.Forms.MessageBox]::Show(
                "Engine pin applied successfully!`n`n" +
                "App  : $($selectedApp.Name)`n" +
                "Size : $selectedLabel",
                "Success", "OK", "Information") | Out-Null
        }
        catch {
            $statusLabel.Text = "Failed to apply engine pin."
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to apply engine pin:`n`n$_",
                "API Error", "OK", "Error") | Out-Null
        }
        finally {
            $form.Cursor    = [System.Windows.Forms.Cursors]::Default
            $btnPin.Enabled = $true
        }
    })

    [void]$form.ShowDialog()
}

# =============================================================================
# ENTRY POINT
# =============================================================================
Show-QlikPinForm