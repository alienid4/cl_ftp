"""
Main blueprint — 首頁 / Dashboard
"""
from flask import Blueprint, render_template
from flask_login import login_required, current_user
from ..db import get_user_pending_batches, get_business_codes

main_bp = Blueprint('main', __name__, template_folder='../templates')


@main_bp.route('/')
@login_required
def home():
    """首頁: 待簽核 + 我負責的業務"""
    pending_batches = get_user_pending_batches(current_user.ad_account)
    owned_codes = [bc for bc in get_business_codes() if bc.get('owner_ad') == current_user.ad_account]

    return render_template(
        'home.html',
        pending_batches=pending_batches,
        owned_codes=owned_codes,
    )
