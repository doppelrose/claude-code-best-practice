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

# Строка запроса доступа к камере берётся из InfoPlist.xcstrings — как в самом приложении,
# чтобы source.json не расходился с тем, что видит пользователь.
INFOPLIST_STRINGS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AIHomework", "Resources", "InfoPlist.xcstrings")


def camera_usage_description(language="en"):
    with open(INFOPLIST_STRINGS, encoding="utf-8") as handle:
        strings = json.load(handle)["strings"]
    return strings["NSCameraUsageDescription"]["localizations"][language]["stringUnit"]["value"]


description = (
    "Решатель школьных заданий: скриншот по кнопке действия или фото, выделение части задания пальцем, "
    "пошаговые решения. Без API типовые задачи по математике, физике, химии и информатике решаются прямо на iPhone; "
    "с API текст задания уходит в нейросеть по вашему ключу (изображение — только если вы это включили).\n\n"
    "A homework solver: Action Button screenshot or photo, circle the task, step-by-step solutions. "
    "Without an API, standard problems are solved on the iPhone; with an API, the task text goes to an AI model "
    "with your key (the image only if you turn that on)."
)

source = {
    "name": "AI Homework",
    "identifier": args.bundle_id + ".source",
    "sourceURL": args.source_url,
    "subtitle": "Homework solver",
    "description": description,
    "iconURL": args.icon_url,
    "tintColor": "#7C5CFC",
    "apps": [
        {
            "name": "AI Homework",
            "bundleIdentifier": args.bundle_id,
            "developerName": "AI Homework",
            "subtitle": "Решение школьных заданий",
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
                    "NSCameraUsageDescription": camera_usage_description()
                },
            },
        }
    ],
    "news": [],
}

with open(args.out, "w", encoding="utf-8") as handle:
    json.dump(source, handle, ensure_ascii=False, indent=2)
print(f"wrote {args.out} for version {args.version} ({args.build})")
