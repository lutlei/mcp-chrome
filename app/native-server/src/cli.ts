#!/usr/bin/env node

import { program } from 'commander';
import * as fs from 'fs';
import * as path from 'path';
import {
  tryRegisterUserLevelHost,
  colorText,
  registerWithElevatedPermissions,
  ensureExecutionPermissions,
} from './scripts/utils';
import { BrowserType, parseBrowserType, detectInstalledBrowsers } from './scripts/browser-config';

// Import writeNodePath from postinstall
async function writeNodePath(): Promise<void> {
  try {
    const nodePath = process.execPath;
    const nodePathFile = path.join(__dirname, 'node_path.txt');

    console.log(colorText(`Writing Node.js path: ${nodePath}`, 'blue'));
    fs.writeFileSync(nodePathFile, nodePath, 'utf8');
    console.log(colorText('✓ Node.js path written for run_host scripts', 'green'));
  } catch (error: any) {
    console.warn(colorText(`⚠️ Failed to write Node.js path: ${error.message}`, 'yellow'));
  }
}

program
  .version(require('../package.json').version)
  .description('Mcp Chrome Bridge - Local service for communicating with Chrome extension');

// Register Native Messaging host
program
  .command('register')
  .description('Register Native Messaging host')
  .option('-f, --force', 'Force re-registration')
  .option('-s, --system', 'Use system-level installation (requires administrator/sudo privileges)')
  .option('-b, --browser <browser>', 'Register for specific browser (chrome, chromium, or all)')
  .option('-d, --detect', 'Auto-detect installed browsers')
  .action(async (options) => {
    try {
      // Write Node.js path for run_host scripts
      await writeNodePath();

      // Determine which browsers to register
      let targetBrowsers: BrowserType[] | undefined;

      if (options.browser) {
        if (options.browser.toLowerCase() === 'all') {
          targetBrowsers = [BrowserType.CHROME, BrowserType.CHROMIUM];
          console.log(colorText('Registering for all supported browsers...', 'blue'));
        } else {
          const browserType = parseBrowserType(options.browser);
          if (!browserType) {
            console.error(
              colorText(
                `Invalid browser: ${options.browser}. Use 'chrome', 'chromium', or 'all'`,
                'red',
              ),
            );
            process.exit(1);
          }
          targetBrowsers = [browserType];
        }
      } else if (options.detect) {
        targetBrowsers = detectInstalledBrowsers();
        if (targetBrowsers.length === 0) {
          console.log(
            colorText(
              'No supported browsers detected, will register for Chrome and Chromium',
              'yellow',
            ),
          );
          targetBrowsers = undefined; // Will use default behavior
        }
      }
      // If neither option specified, tryRegisterUserLevelHost will detect browsers

      // Detect if running with root/administrator privileges
      const isRoot = process.getuid && process.getuid() === 0; // Unix/Linux/Mac

      let isAdmin = false;
      if (process.platform === 'win32') {
        try {
          isAdmin = require('is-admin')(); // Windows requires additional package
        } catch (error) {
          console.warn(
            colorText('Warning: Unable to detect administrator privileges on Windows', 'yellow'),
          );
          isAdmin = false;
        }
      }

      const hasElevatedPermissions = isRoot || isAdmin;

      // If --system option is specified or running with root/administrator privileges
      if (options.system || hasElevatedPermissions) {
        // TODO: Update registerWithElevatedPermissions to support multiple browsers
        await registerWithElevatedPermissions();
        console.log(
          colorText('System-level Native Messaging host registered successfully!', 'green'),
        );
        console.log(
          colorText(
            'You can now use connectNative in Chrome extension to connect to this service.',
            'blue',
          ),
        );
      } else {
        // Regular user-level installation
        console.log(colorText('Registering user-level Native Messaging host...', 'blue'));
        const success = await tryRegisterUserLevelHost(targetBrowsers);

        if (success) {
          console.log(colorText('Native Messaging host registered successfully!', 'green'));
          console.log(
            colorText(
              'You can now use connectNative in Chrome extension to connect to this service.',
              'blue',
            ),
          );
        } else {
          console.log(
            colorText(
              'User-level registration failed, please try the following methods:',
              'yellow',
            ),
          );
          console.log(colorText('  1. sudo mcp-chrome-bridge register', 'yellow'));
          console.log(colorText('  2. mcp-chrome-bridge register --system', 'yellow'));
          process.exit(1);
        }
      }
    } catch (error: any) {
      console.error(colorText(`Registration failed: ${error.message}`, 'red'));
      process.exit(1);
    }
  });

// Fix execution permissions
program
  .command('fix-permissions')
  .description('Fix execution permissions for native host files')
  .action(async () => {
    try {
      console.log(colorText('Fixing execution permissions...', 'blue'));
      await ensureExecutionPermissions();
      console.log(colorText('✓ Execution permissions fixed successfully!', 'green'));
    } catch (error: any) {
      console.error(colorText(`Failed to fix permissions: ${error.message}`, 'red'));
      process.exit(1);
    }
  });

// Update port in stdio-config.json
program
  .command('update-port <port>')
  .description('Update the port number in stdio-config.json')
  .action(async (port: string) => {
    try {
      const portNumber = parseInt(port, 10);
      if (isNaN(portNumber) || portNumber < 1 || portNumber > 65535) {
        console.error(colorText('Error: Port must be a valid number between 1 and 65535', 'red'));
        process.exit(1);
      }

      const configPath = path.join(__dirname, 'mcp', 'stdio-config.json');

      if (!fs.existsSync(configPath)) {
        console.error(colorText(`Error: Configuration file not found at ${configPath}`, 'red'));
        process.exit(1);
      }

      const configData = fs.readFileSync(configPath, 'utf8');
      const config = JSON.parse(configData);

      const currentUrl = new URL(config.url);
      currentUrl.port = portNumber.toString();
      config.url = currentUrl.toString();

      fs.writeFileSync(configPath, JSON.stringify(config, null, 4));

      console.log(colorText(`✓ Port updated successfully to ${portNumber}`, 'green'));
      console.log(colorText(`Updated URL: ${config.url}`, 'blue'));
    } catch (error: any) {
      console.error(colorText(`Failed to update port: ${error.message}`, 'red'));
      process.exit(1);
    }
  });

// Configure host binding
program
  .command('configure-host [host]')
  .description('Configure the MCP server host binding (IP address to listen on)')
  .option('-i, --info', 'Show current configuration')
  .option('-r, --reset', 'Reset to default (0.0.0.0)')
  .option('-t, --tailscale', 'Auto-detect and use Tailscale IP')
  .option('-l, --local', 'Use localhost only (127.0.0.1)')
  .option('-g, --global', 'Use all interfaces (0.0.0.0)')
  .action(async (host: string | undefined, options: any) => {
    try {
      const { execSync } = require('child_process');
      const os = require('os');
      const configureScriptPath = path.join(__dirname, 'scripts', 'configure-host.sh');

      // Check if script exists
      if (!fs.existsSync(configureScriptPath)) {
        console.error(
          colorText(`Error: configure-host.sh script not found at ${configureScriptPath}`, 'red'),
        );
        console.log(
          colorText('Please ensure the package is properly installed and rebuilt.', 'yellow'),
        );
        process.exit(1);
      }

      // Build command arguments
      const args: string[] = [];
      if (options.info) args.push('--info');
      else if (options.reset) args.push('--reset');
      else if (options.tailscale) args.push('--tailscale');
      else if (options.local) args.push('--local');
      else if (options.global) args.push('--global');
      else if (host) args.push(host);
      else {
        console.error(colorText('Error: Please provide a host IP or use an option flag', 'red'));
        program.outputHelp();
        process.exit(1);
      }

      // Execute the script
      execSync(`bash "${configureScriptPath}" ${args.join(' ')}`, {
        stdio: 'inherit',
        cwd: path.dirname(configureScriptPath),
      });
    } catch (error: any) {
      if (error.status !== undefined) {
        // Script exited with non-zero code
        process.exit(error.status);
      } else {
        console.error(colorText(`Failed to configure host: ${error.message}`, 'red'));
        process.exit(1);
      }
    }
  });

program.parse(process.argv);

// If no command provided, show help
if (!process.argv.slice(2).length) {
  program.outputHelp();
}
