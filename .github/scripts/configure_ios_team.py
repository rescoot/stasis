#!/usr/bin/env python3
"""Configure the app and embedded widget for App Store distribution in CI."""

import re
import sys
from pathlib import Path

PROJECT = Path("ios/Runner.xcodeproj/project.pbxproj")
TARGETS = {
    "97C147071CF9000F007C117D": ("de.freal.unustasis", "Stasis App Store CI"),
    "B3D281C22E214678001687E0": (
        "de.freal.unustasis.ScooterWidget",
        "Stasis Widget App Store CI",
    ),
}


def configure(text, team_id):
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("APPLE_TEAM_ID must be a ten-character Apple team ID")

    for config_id, (bundle_id, profile) in TARGETS.items():
        pattern = rf"(\t\t{config_id} /\* Release \*/ = \{{.*?\t\t\}};)"
        match = re.search(pattern, text, flags=re.S)
        if not match:
            raise ValueError(f"missing Release configuration {config_id}")
        block = match.group(1)
        if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};" not in block:
            raise ValueError(f"unexpected bundle ID in Release configuration {config_id}")
        block, count = re.subn(
            r"DEVELOPMENT_TEAM = [A-Z0-9]{10};",
            f"DEVELOPMENT_TEAM = {team_id};",
            block,
        )
        if count != 1:
            raise ValueError(f"expected one development team in {config_id}")
        style = "CODE_SIGN_STYLE = Automatic;"
        if style in block:
            block = block.replace(style, "CODE_SIGN_STYLE = Manual;", 1)
        else:
            block = block.replace(
                "CODE_SIGN_ENTITLEMENTS = ",
                "CODE_SIGN_STYLE = Manual;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = ",
                1,
            )
        block = block.replace(
            'PRODUCT_NAME = "$(TARGET_NAME)";',
            f'PRODUCT_NAME = "$(TARGET_NAME)";\n'
            f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile}";',
            1,
        )
        if f'PROVISIONING_PROFILE_SPECIFIER = "{profile}";' not in block:
            raise ValueError(f"could not set the signing profile for {config_id}")
        text = text[:match.start()] + block + text[match.end():]
    return text


if __name__ == "__main__":
    try:
        PROJECT.write_text(configure(PROJECT.read_text(), sys.argv[1]))
    except (IndexError, OSError, ValueError) as error:
        sys.exit(f"iOS signing configuration failed: {error}")
