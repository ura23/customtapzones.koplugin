# Custom Tap Zones Plugin for KOReader

## Description
This plugin allows users to configure custom tap zones for page turning. It provides the ability to replace the default tap zones with a user-defined grid, where each cell can be configured to perform a specific action.

## Screenshots

<div align="center">
  <img width="571" height="379" alt="Main UI" src="https://github.com/user-attachments/assets/f78e68f8-23ab-45d0-8469-583c833c00e1" />
  <p><em>Main UI</em></p>
</div>

<div align="center">
  <img width="676" height="350" alt="Edit tap zones" src="https://github.com/user-attachments/assets/91096a56-73fb-45db-a8fb-aa5f6bb0dfae" />
  <p><em>Edit tap zones</em></p>
</div>

## Features
* **Customizable grid size:** Users can change the number of columns and rows for the tap zone grid (from 2x2 up to 8x8).
* **Action assignment:** Each cell in the grid can be assigned one of three actions:
  * Page forward
  * Page backward
  * Ignore tap (disables page turning in this zone, resulting in no reaction to touch)
* **Orientation support:** The plugin maintains independent grid configurations for portrait and landscape reading modes.
* **Layout copying:** The configured grid layout can be quickly copied from portrait to landscape mode and vice versa.
* **Visual editor:** A built-in graphical editor allows users to configure the actions for each cell directly through the device interface. The editor also warns the user if an assigned zone overlaps with the system menu invocation zones (the top and bottom parts of the screen).
* **Zone visualization:** Includes an option to temporarily display the currently configured grid over the screen for verifying and testing the layout.
* **State management:** The plugin can be easily activated or deactivated via the settings menu.
