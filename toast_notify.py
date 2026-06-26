"""Windows toast notification via PowerShell"""
import subprocess, sys

title = sys.argv[1] if len(sys.argv) > 1 else "Hermes Agent"
message = sys.argv[2] if len(sys.argv) > 2 else "Task completed."

ps_script = f'''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$template.GetElementsByTagName("text")[0].AppendChild($template.CreateTextNode("{title}")) > $null
$template.GetElementsByTagName("text")[1].AppendChild($template.CreateTextNode("{message}")) > $null
$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Hermes").Show($toast)
'''

subprocess.run(["powershell", "-NoProfile", "-Command", ps_script],
               capture_output=True)
print(f"Notification sent: {title} - {message}")
