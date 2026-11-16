# FocusNotch

[![Cloud build](https://github.com/VidhyashreeX/FocusNotch/actions/workflows/build.yml/badge.svg?branch=dev)](https://github.com/VidhyashreeX/FocusNotch/actions/workflows/build.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

FocusNotch is a productivity-focused macOS notch application. It adds a built-in focus timer while preserving the media controls, battery information, calendar, shelf, and other features inherited from [Boring Notch](https://github.com/TheBoredTeam/boring.notch).

> [!IMPORTANT]
> FocusNotch is currently a work in progress. A public downloadable release is being prepared and tested. The application bundle may temporarily appear as **Boring Notch** until the product-renaming work is completed.

## Features

### Focus timer

- Focus, short-break, and long-break phases
- Customizable phase durations
- Configurable number of focus sessions before a long break
- Optional next-phase auto-start
- Countdown display in the closed notch
- End-of-phase notification and sound options
- Persistent timer history

### Existing notch features

- Music and media controls
- Battery and charging information
- Calendar and reminders integration
- File shelf and sharing tools
- System display controls and other Boring Notch capabilities

## Download

Tested builds will be published on the [FocusNotch Releases page](https://github.com/VidhyashreeX/FocusNotch/releases).

There is no public FocusNotch release yet. Please do not download GitHub's automatic **Source code** archive expecting it to contain an installable application. Wait for a release that includes a macOS `.zip` attachment.

### Installing a future test release

1. Open the [Releases page](https://github.com/VidhyashreeX/FocusNotch/releases).
2. Download the macOS ZIP attached to the latest FocusNotch test release.
3. Double-click the ZIP to extract the application.
4. Move the application into the **Applications** folder.
5. Control-click the application and choose **Open**.
6. If macOS blocks it, open **System Settings > Privacy & Security**, click **Open Anyway**, and confirm **Open**.

> [!WARNING]
> Early free test builds are unsigned/ad-hoc signed and are not notarized by Apple. macOS will display a security warning. Only download builds from this repository, and do not disable Gatekeeper globally.

## Project status

- Development branch: `dev`
- Cloud builds: GitHub Actions using the repository's Xcode project and scheme
- Current distribution: unsigned testing builds only
- Planned before a broader release: finish product renaming, retest installation, and publish a verified pre-release

## Building and testing

The cloud workflow is defined in [`.github/workflows/build.yml`](.github/workflows/build.yml). It builds the macOS application, runs the available automated checks, verifies the application bundle, and packages it as a ZIP artifact.

To run it from GitHub:

1. Open the repository's **Actions** tab.
2. Select the FocusNotch macOS build workflow.
3. Click **Run workflow** and choose `dev`.
4. Open the completed run to read its logs and download its temporary artifact.

GitHub Actions artifacts are intended for development verification. Public downloads will be attached to the [Releases page](https://github.com/VidhyashreeX/FocusNotch/releases).

## Contributing

Contributions are welcome. Keep each change isolated so that it can be reviewed safely:

1. Fork this repository to your own GitHub account.
2. Create a new branch for one feature or fix.
3. Make and test your changes on that branch.
4. Open a pull request targeting the `dev` branch of this repository.

Please do not combine unrelated changes in one pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for the upstream contribution guidance that still applies to this GPL project.

## License and attribution

FocusNotch is free and open-source software licensed under [GPL-3.0](LICENSE).

This project is based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by The Bored Team and its contributors. The original copyright notices, GPL-3.0 license, commit history, and third-party attribution are preserved. See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for dependency acknowledgments.

FocusNotch is an independent customization and is not presented as an official release of The Bored Team.
