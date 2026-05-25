"""
SF Portal — Mail helper

send_mail(to, subject, body):
    - 從 Flask config 讀 SMTP_SERVER / SMTP_PORT / SMTP_FROM
    - fail 只 log 不 raise (mail 失敗不該擋簽核流程)

to 可以是 str 或 list of str (multiple recipients).
"""
import smtplib
from email.mime.text import MIMEText
from email.utils import formatdate, make_msgid
from flask import current_app


def send_mail(to, subject, body, content_type='plain'):
    cfg = current_app.config
    server = cfg.get('SMTP_SERVER')
    port = int(cfg.get('SMTP_PORT') or 25)
    sender = cfg.get('SMTP_FROM') or 'sf-noreply@sflab'

    if not server:
        current_app.logger.warning('[MAIL] SMTP_SERVER 未設, 跳過寄信 subject=' + subject)
        return False

    recipients = to if isinstance(to, list) else [to]
    recipients = [r for r in recipients if r]
    if not recipients:
        current_app.logger.info('[MAIL] 無收件人, 跳過: subject=' + subject)
        return False

    try:
        msg = MIMEText(body, content_type, 'utf-8')
        msg['Subject'] = subject
        msg['From'] = sender
        msg['To'] = ', '.join(recipients)
        msg['Date'] = formatdate(localtime=True)
        msg['Message-ID'] = make_msgid(domain='sflab')

        with smtplib.SMTP(server, port, timeout=5) as s:
            if cfg.get('SMTP_USE_TLS'):
                s.starttls()
            s.send_message(msg)
        current_app.logger.info('[MAIL] 寄出 → ' + ', '.join(recipients) + ' / ' + subject)
        return True
    except Exception as e:
        current_app.logger.warning('[MAIL] 寄信失敗 (' + server + ':' + str(port) + '): ' + str(e))
        return False


def notify_approvers(group_members, batch_id, business_name, file_count, total_size_humanized, portal_url):
    """寄通知信給簽核人 (新批次來時)"""
    recipients = [m['mail'] for m in group_members if m.get('mail')]
    if not recipients:
        return False
    subject = '[SF Portal] ' + (business_name or batch_id) + ' 待您簽核 (' + str(file_count) + ' 檔, ' + total_size_humanized + ')'
    body = (
        '您有新批次需要簽核:\n\n'
        '  業務: ' + (business_name or '-') + '\n'
        '  批次 ID: ' + batch_id + '\n'
        '  檔數: ' + str(file_count) + '\n'
        '  總大小: ' + total_size_humanized + '\n\n'
        'ANY 制 — 任 1 位同意即放行, 任 1 位駁回即駁回. 7 天無人處理自動駁回.\n\n'
        '簽核連結: ' + portal_url + '\n'
    )
    return send_mail(recipients, subject, body)


def notify_downloaders(group_members, business_name, samba_path, file_names):
    """寄通知信給可下載群組 (檔搬到 samba 後)"""
    recipients = [m['mail'] for m in group_members if m.get('mail')]
    if not recipients:
        return False
    subject = '[SF Portal] ' + (business_name or '-') + ' 新檔可下載 (' + str(len(file_names)) + ' 個檔)'
    body = (
        '您所屬群組可下載的新檔已放行:\n\n'
        '  業務: ' + (business_name or '-') + '\n'
        '  下載路徑: ' + samba_path + '\n'
        '  保留期: 7 天 (到期自動刪)\n\n'
        '檔案清單:\n'
        + '\n'.join('  - ' + f for f in file_names)
        + '\n\n'
        'SMB 拖拉: 開檔案總管打 ' + samba_path + '\n'
        'Portal 下載: 進「我的可下載」頁逐個下載或打包 ZIP.\n'
    )
    return send_mail(recipients, subject, body)


def notify_uploader_rejected(uploader_mail, batch_id, business_name, reason, file_names):
    """寄駁回信給上傳人"""
    if not uploader_mail:
        return False
    subject = '[SF Portal] ' + (business_name or batch_id) + ' 批次已駁回'
    body = (
        '您上傳的批次已被駁回:\n\n'
        '  業務: ' + (business_name or '-') + '\n'
        '  批次 ID: ' + batch_id + '\n'
        '  駁回原因: ' + (reason or '(未填)') + '\n\n'
        '檔案清單:\n'
        + '\n'.join('  - ' + f for f in file_names)
        + '\n\n'
        '檔案會留在 inbound/ 7 天後自動刪. 修正後可重新上傳.\n'
    )
    return send_mail(uploader_mail, subject, body)
