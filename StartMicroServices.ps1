Param(
    [string]$configFilePath = ".\StartMicroServicesConfig.json"
)
begin {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $ErrorActionPreference = "Stop"

    # Make unicode icons compatible
    # https://stackoverflow.com/questions/77269886/winforms-in-powershell-not-able-to-display-unicode-character
    try
    {
        [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    }
    catch
    {
    }

    # https://stackoverflow.com/questions/55896492/terminate-process-tree-in-powershell-given-a-process-id
    function global:Stop-ProcessTree {
        Param([int]$ppid)
        Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ppid } | ForEach-Object { Stop-ProcessTree $_.ProcessId }
        # Stopping process in a tree could also stop other processes. Which could
        # throw process with id not found error. We don't want to spam the error message
        # in this case. Hence we need "-ErrorAction SilentlyContinue"
        Stop-Process -Id $ppid -ErrorAction SilentlyContinue
    }
    function global:Start-MicroService
    {
        param(
            [string]$name,
            [string]$path,
            [ValidateSet('AngularApp','DotnetApp')]
            [System.String]$applicationType,
            [ValidateSet('Release','Debug')]
            [System.String]$runMode = 'Release'
        )

        if ($applicationType -eq 'AngularApp')
        {
            Write-Host "Starting $name..."
            $process = Start-Process cmd -ArgumentList "/c title $name & cd $path & ng serve" -PassThru
        }
        elseif ($applicationType -eq 'DotnetApp')
        {
            Write-Host "Starting $name in $runMode mode..."
            $process = Start-Process cmd -ArgumentList "/c title $name & dotnet run --project $path -c $runMode" -PassThru
        }

        # Avoid clicking too fast to start/stop the process which could cause issues.
        Start-Sleep -Milliseconds 600

        return $process
    }
}
process {
    $Config = (Get-Content $configFilePath | Out-String | ConvertFrom-Json)

    $form = New-Object System.Windows.Forms.Form
    $form.Text =  $Config.WindowTitle
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9);
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size($Config.WindowWidth,$Config.WindowHeight)

    $checkboxSize = New-Object System.Drawing.Size(130,25)
    
    $yOffSet = 30
    $microServices = @{}
    for ($i = 0; $i -lt $Config.MicroServices.Length ; $i++)
    {
        if ($Config.MicroServices[$i].ApplicationType -eq "DotnetApp")
        {
            $panel = New-Object System.Windows.Forms.Panel
            $panel.Location = New-Object System.Drawing.Point(150, ($yOffSet - 5))
            $panel.size = '135,25'

            $releaseModeRadioButton = New-Object System.Windows.Forms.RadioButton
            $releaseModeRadioButton.Location = '5,5'
            $releaseModeRadioButton.size = '70,25'
            $releaseModeRadioButton.Checked = $true 
            $releaseModeRadioButton.Text = "Release"

            $debugModeRadioButton = New-Object System.Windows.Forms.RadioButton
            $debugModeRadioButton.Location = '75,5'
            $debugModeRadioButton.Text = "Debug"

            $panel.Controls.Add($releaseModeRadioButton);
            $panel.Controls.Add($debugModeRadioButton);

            $form.Controls.Add($panel)
        }

        $checkBox = New-Object System.Windows.Forms.CheckBox
        $checkBox.Appearance = 'Button'
        $checkBox.Text = $Config.MicroServices[$i].Name
        $checkBox.Size = $checkboxSize
        $checkBox.Location = New-Object System.Drawing.Point(15, $yOffSet)
        $clickEvent = {
            if ($checkBox.Checked)
            {
                $checkBox.BackColor = "PaleGreen"
                Write-Host $releaseModeRadioButton.Checked
                $runMode = If ($releaseModeRadioButton.Checked) { "Release" } Else { "Debug" }
                $microServices[$Config.MicroServices[$i].Name] = Start-MicroService $Config.MicroServices[$i].Name $Config.MicroServices[$i].Path $Config.MicroServices[$i].ApplicationType $runMode
            }
            else
            {
                $checkBox.BackColor = "Transparent"
                Write-Host "Stopping $($Config.MicroServices[$i].Name)..."
                Stop-ProcessTree $microServices[$Config.MicroServices[$i].Name].Id
            }
        }.GetNewClosure()

        $checkBox.Add_Click($clickEvent)
        $form.Controls.Add($checkBox)

        $yOffSet += 25;
    }

    $form.TopMost = $true
    $form.ShowDialog()
    $form.Dispose()

    Write-Host -NoNewLine 'Press any key to exit...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

