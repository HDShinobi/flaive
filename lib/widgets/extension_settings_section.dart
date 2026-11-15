import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/installed_extension.dart';
import '../services/backend_bridge.dart';

class ExtensionSettingsSection extends StatefulWidget {
  const ExtensionSettingsSection({
    super.key,
    required this.ext,
    required this.bridge,
  });

  final InstalledExtension ext;
  final BackendBridge bridge;

  @override
  State<ExtensionSettingsSection> createState() =>
      _ExtensionSettingsSectionState();
}

class _ExtensionSettingsSectionState extends State<ExtensionSettingsSection> {
  Map<String, dynamic> _stored = {};
  bool _loaded = false;
  bool _loadFailed = false;
  bool _actionRunning = false;
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.bridge.getExtensionSettings(widget.ext.id);
      if (!mounted) return;
      setState(() {
        _stored = Map.of(settings);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Merge at execution time, after the previous save has committed. Defaults
  // must never enter this map: only user-saved URLs grant network access.
  Future<void> _save(Map<String, dynamic> updates) {
    final id = widget.ext.id;
    final bridge = widget.bridge;
    final task = _pendingSave.then((_) async {
      final merged = {..._stored, ...updates};
      await bridge.setExtensionSettings(id, merged);
      _stored = merged;
      if (mounted) setState(() {});
    });
    // A failed save must not poison the queue or change the committed map.
    _pendingSave = task.catchError((Object _) {});
    return task;
  }

  Future<void> _change(String key, Object? value) async {
    try {
      await _save({key: value});
    } catch (_) {
      if (mounted) _message(AppLocalizations.of(context).extSettingsSaveFailed);
    }
  }

  Future<void> _edit(ExtensionSetting setting, Object? value) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _SettingEditDialog(setting: setting, value: value),
    );
    if (mounted && result != null) await _change(setting.key, result);
  }

  Future<void> _select(ExtensionSetting setting, Object? value) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(setting.label),
        children: [
          for (final option in setting.options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option),
              child: Row(
                children: [
                  Expanded(child: Text(option)),
                  if (option == value) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (mounted && selected != null) await _change(setting.key, selected);
  }

  Future<void> _runAction(ExtensionSetting setting) async {
    setState(() => _actionRunning = true);
    final t = AppLocalizations.of(context);
    try {
      await _pendingSave;
      if (!mounted) return;
      final result = await widget.bridge.invokeExtensionAction(
        widget.ext.id,
        setting.action!,
      );
      if (!mounted) return;
      final nested = result['result'];
      final payload = nested is Map
          ? Map<String, dynamic>.from(nested)
          : result;
      if (result['success'] == false || payload['success'] != true) {
        _message(
          (payload['error'] ?? result['error'] ?? t.extActionFailed).toString(),
        );
        return;
      }
      final updates = payload['setting_updates'];
      if (updates is Map && updates.isNotEmpty) {
        try {
          await _save(Map<String, dynamic>.from(updates));
        } catch (_) {
          _message(t.extSettingsSaveFailed);
          return;
        }
      }
      if (!mounted) return;
      final authUrl = payload['open_auth_url'];
      if (authUrl is String && authUrl.isNotEmpty) {
        final uri = Uri.tryParse(authUrl);
        if (uri == null ||
            !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          _message(t.extAuthOpenFailed);
        }
      }
      final message = payload['message'];
      if (message is String && message.isNotEmpty) _message(message);
    } catch (_) {
      _message(t.extActionFailed);
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Widget _row(ExtensionSetting setting) {
    final t = AppLocalizations.of(context);
    final value = _stored[setting.key] ?? setting.defaultValue;
    final empty = value == null || value.toString().trim().isEmpty;
    final subtitle = [
      if (setting.description?.isNotEmpty == true) setting.description!,
      if (setting.type != 'button' && setting.type != 'boolean')
        empty
            ? t.extSettingNotSet
            : setting.secret
            ? '••••'
            : value.toString(),
      if (setting.required && empty) t.extSettingRequiredEmpty,
    ].join('\n');
    final supported = const [
      'string',
      'number',
      'boolean',
      'select',
      'button',
    ].contains(setting.type);
    final enabled = _loaded && supported;
    if (setting.type == 'boolean') {
      return SwitchListTile(
        title: Text(setting.label),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        value: value == true,
        onChanged: enabled ? (v) => _change(setting.key, v) : null,
      );
    }
    final isButton = setting.type == 'button';
    final canTap =
        enabled &&
        (!isButton || (!_actionRunning && setting.action?.isNotEmpty == true));
    return ListTile(
      enabled: canTap,
      title: Text(setting.label),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: isButton
          ? const Icon(Icons.play_arrow)
          : const Icon(Icons.chevron_right),
      onTap: !canTap
          ? null
          : () {
              if (isButton) {
                _runAction(setting);
              } else if (setting.type == 'select') {
                _select(setting, value);
              } else {
                _edit(setting, value);
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.extSettingsTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (!_loaded && !_loadFailed)
          const Center(child: CircularProgressIndicator()),
        if (_loadFailed) Text(t.extSettingsLoadFailed),
        Card(child: Column(children: widget.ext.settings.map(_row).toList())),
      ],
    );
  }
}

class _SettingEditDialog extends StatefulWidget {
  const _SettingEditDialog({required this.setting, required this.value});
  final ExtensionSetting setting;
  final Object? value;

  @override
  State<_SettingEditDialog> createState() => _SettingEditDialogState();
}

class _SettingEditDialogState extends State<_SettingEditDialog> {
  late final _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final setting = widget.setting;
    return AlertDialog(
      title: Text(setting.label),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: setting.secret,
        autocorrect: !setting.secret,
        enableSuggestions: !setting.secret,
        keyboardType: setting.type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          hintText: setting.description,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () {
            Object value = _controller.text;
            if (setting.type == 'number') {
              final number = num.tryParse(_controller.text);
              if (number == null || !number.isFinite) {
                setState(() => _error = t.extSettingInvalidNumber);
                return;
              }
              value = number;
            }
            Navigator.pop(context, value);
          },
          child: Text(t.save),
        ),
      ],
    );
  }
}
