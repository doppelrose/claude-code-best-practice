#!/usr/bin/env python3
"""Генерирует source.json — источник для SideStore / AltStore (формат AltStore source v2).

Источник добавляется в SideStore один раз; после этого новые сборки из CI
приходят как обычные обновления прямо на iPhone.

Использование:
    make_sidestore_source.py --ipa AIHomework.ipa --version 1.0.42 --build 42 \
        --download-url https://.../AIHomework.ipa --icon-url https://.../AppIcon.png \
        --source-url https://.../source.json --out source.json
"""
import argparse
import datetime
import json
import os

parser = argparse.ArgumentParser()
parser.add_argument("--ipa", required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
parser.add_argument("--download-url", required=True)
parser.add_argument("--icon-url", required=True)
parser.add_argument("--source-url", required=True)
parser.add_argument("--bundle-id", default="com.example.aihomework")
parser.add_argument("--out", default="source.json")
args = parser.parse_args()

description = (
    "Решатель школьных заданий, который работает прямо на iPhone: камера, выделение части задания, "
    "распознавание текста, пошаговые решения по математике, физике, химии и информатике. "
    "Без API-ключей, регистрации и серверов.\n\n"
    "A homework solver that runs entirely on your iPhone. No API keys, sign-up or servers."
)

source = {
    "name": "AI Homework",
    "identifier": args.bundle_id + ".source",
    "sourceURL": args.source_url,
    "subtitle": "On-device homework solver",
    "description": description,
    "iconURL": args.icon_url,
    "tintColor": "#7C5CFC",
    "apps": [
        {
            "name": "AI Homework",
            "bundleIdentifier": args.bundle_id,
            "developerName": "AI Homework",
            "subtitle": "Решение заданий на устройстве",
            "localizedDescription": description,
            "iconURL": args.icon_url,
            "tintColor": "#7C5CFC",
            "category": "education",
            "screenshots": [],
            "versions": [
                {
                    "version": args.version,
                    "buildVersion": str(args.build),
                    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "localizedDescription": f"Сборка {args.build} из GitHub Actions.",
                    "downloadURL": args.download_url,
                    "size": os.path.getsize(args.ipa),
                    "minOSVersion": "17.0",
                }
            ],
            "appPermissions": {
                "entitlements": [],
                "privacy": {
                    "NSCameraUsageDescription": "The camera is used to take a photo of a homework problem. Photos are processed on this device."
                },
            },
        }
    ],
    "news": [],
}

with open(args.out, "w", encoding="utf-8") as handle:
    json.dump(source, handle, ensure_ascii=False, indent=2)
print(f"wrote {args.out} for version {args.version} ({args.build})")
