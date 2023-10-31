Param(
    [string]$configFilePath = ".\StartMicroServicesConfig.json"
)
begin {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $ErrorActionPreference = "Stop"

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
    $form.Text =  $Config.windowTitle
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9);
    $form.StartPosition = 'CenterScreen'

    $windowHeight = 25 * $Config.microServices.Length + 100;
    $form.Size = New-Object System.Drawing.Size(480, $windowHeight)

    $checkboxSize = New-Object System.Drawing.Size(130,25)
    $radioButtonSize = New-Object System.Drawing.Size(90,25)
    
    $yOffSet = 25
    $microServices = @{}
    for ($i = 0; $i -lt $Config.microServices.Length ; $i++)
    {
        if ($Config.microServices[$i].ApplicationType -eq "DotnetApp")
        {
            # Add options to chose run mode
            $panel = New-Object System.Windows.Forms.Panel
            $panel.Location = New-Object System.Drawing.Point(150, ($yOffSet - 5))
            $panel.size = '280,25'

            $releaseModeRadioButton = New-Object System.Windows.Forms.RadioButton
            $releaseModeRadioButton.Location = '5,5'
            $releaseModeRadioButton.size = $radioButtonSize
            $releaseModeRadioButton.Checked = $true 
            $releaseModeRadioButton.Text = "Run Release"

            $debugModeRadioButton = New-Object System.Windows.Forms.RadioButton
            $debugModeRadioButton.size = $radioButtonSize
            $debugModeRadioButton.Location = '100,5'
            $debugModeRadioButton.Text = "Run Debug"

            $debugInVsRadioButton = New-Object System.Windows.Forms.RadioButton
            $debugModeRadioButton.size = $radioButtonSize
            $debugInVsRadioButton.Location = '190,5'
            $debugInVsRadioButton.Text = "Debug in VS"

            $panel.Controls.Add($releaseModeRadioButton);
            $panel.Controls.Add($debugModeRadioButton);
            $panel.Controls.Add($debugInVsRadioButton);

            $form.Controls.Add($panel)
        }

        $checkBox = New-Object System.Windows.Forms.CheckBox
        $checkBox.Appearance = 'Button'
        $checkBox.Text = $Config.microServices[$i].Name
        $checkBox.Size = $checkboxSize
        $checkBox.Location = New-Object System.Drawing.Point(15, $yOffSet)
        $runAppEvent = {
            if ($checkBox.Checked)
            {
                If ($releaseModeRadioButton.Checked)
                { 
                    $checkBox.BackColor = "PaleGreen"
                    $microServices[$Config.microServices[$i].Name] = Start-MicroService $Config.microServices[$i].Name $Config.microServices[$i].Path $Config.microServices[$i].ApplicationType "Release"
                } 
                elseif ($debugModeRadioButton.Checked) 
                {
                    $checkBox.BackColor = "PaleGreen"
                    $microServices[$Config.microServices[$i].Name] = Start-MicroService $Config.microServices[$i].Name $Config.microServices[$i].Path $Config.microServices[$i].ApplicationType "Debug"
                }
                elseif ($debugInVsRadioButton.Checked)
                {
                    $checkBox.Checked = $false;
                    & "$($config.visualStudioPath)\Common7\IDE\devenv.exe" /Command "Debug.Start" /Run $Config.microServices[$i].Path
                }
            }
            else
            {
                $checkBox.BackColor = "Transparent"
                Write-Host "Stopping $($Config.microServices[$i].Name)..."

                if ($microServices[$Config.microServices[$i].Name] -ne $null)
                {
                    Stop-ProcessTree $microServices[$Config.microServices[$i].Name].Id
                }
            }
        }.GetNewClosure()

        $checkBox.Add_Click($runAppEvent)
        $form.Controls.Add($checkBox)

        $yOffSet += 25;
    }

    $form.TopMost = $true
    $form.ShowDialog()
    $form.Dispose()

    Write-Host -NoNewLine 'Press any key to exit...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

