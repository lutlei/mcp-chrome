# Security and Privacy Guidelines

This document outlines security best practices for the Chrome MCP Server project.

## Sensitive Data

The following information should **NEVER** be committed to the repository:

### 1. IP Addresses

- **Tailscale IPs**: Your personal Tailscale IP addresses
- **Local network IPs**: Your local network IP addresses
- **Public IPs**: Any public-facing IP addresses

**Where it appears:**

- Configuration files (`~/.mcp-chrome/host`)
- Environment variables (`MCP_CHROME_HOST`)
- README examples (use placeholders like `YOUR_IP_ADDRESS`)

**Solution:**

- Use environment variables or config files outside the repo
- Use placeholders in documentation
- Add `.mcp-chrome/` to `.gitignore`

### 2. Extension IDs

- **Unpacked extension IDs**: Your local development extension IDs
- **Extension keys**: Chrome extension keys for published extensions

**Where it appears:**

- Native messaging host manifests
- Environment variables (`CHROME_EXTENSION_KEY`)

**Solution:**

- Published extension ID (`hbdgbgagpkpjffpklnamcljpakneikee`) is public - OK to commit
- Unpacked extension IDs should be added to manifest locally, not committed
- Extension keys should use environment variables

### 3. User-Specific Paths

- Installation paths
- User home directories
- System-specific paths

**Where it appears:**

- Log files
- Config files
- Native messaging host manifests

**Solution:**

- All user configs are in `~/.mcp-chrome/` (outside repo) ✅
- Logs are in installation directory (not in repo) ✅

## Configuration Files

### Environment Variables

Use `.env.local` for local configuration (already in `.gitignore`):

```bash
# Copy example file
cp .env.example .env.local

# Edit with your values
# MCP_CHROME_HOST=your-tailscale-ip
# CHROME_EXTENSION_KEY=your-key
```

### User Config Files

Configuration files are stored outside the repository:

- `~/.mcp-chrome/host` - Host IP binding
- `{install_dir}/.mcp-chrome-host` - Installation-level config

These are automatically excluded from git.

## Before Committing

Check for:

- [ ] No hardcoded IP addresses (use placeholders)
- [ ] No personal extension IDs (only published ID)
- [ ] No API keys or secrets
- [ ] No user-specific paths
- [ ] `.env.local` is in `.gitignore`
- [ ] Helper scripts with personal data are excluded

## Example Placeholders

Use these in documentation and examples:

```bash
# IP Addresses
YOUR_IP_ADDRESS
YOUR_TAILSCALE_IP
192.168.x.x  # Generic local network

# Extension IDs
YOUR_EXTENSION_ID  # For unpacked extensions
# Published ID is OK: hbdgbgagpkpjffpklnamcljpakneikee

# Paths
YOUR_INSTALL_PATH
~/.mcp-chrome/  # User home is OK
```

## Security Best Practices

1. **Bind to specific IPs**: Use Tailscale IP instead of `0.0.0.0` when possible
2. **Use environment variables**: For any configurable values
3. **Keep secrets out of code**: Use `.env.local` or system config
4. **Review commits**: Check `git diff` before pushing
5. **Use `.gitignore`**: Ensure sensitive files are excluded
