import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart';

class WebDavConnectionFields extends StatefulWidget {
  const WebDavConnectionFields({
    super.key,
    required this.urlController,
    required this.usernameController,
    required this.passwordController,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController urlController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool enabled;
  final VoidCallback onSubmitted;

  @override
  State<WebDavConnectionFields> createState() => _WebDavConnectionFieldsState();
}

class _WebDavConnectionFieldsState extends State<WebDavConnectionFields> {
  bool _passwordVisible = false;

  @override
  Widget build(BuildContext context) => prism.FilledInputTheme(
    // FilledInputTheme uses this same shape for disabled, enabled and focused
    // borders, so loading the saved config cannot animate the corner radius.
    borderRadius: prism.AppRadius.md,
    fillColor: prism.SurfaceLevel.block.colorOf(
      prism.Theme.of(context).colorScheme,
    ),
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConnectionField(
            label: 'WebDAV 地址',
            child: prism.TextField(
              key: const ValueKey('webdav-url-field'),
              controller: widget.urlController,
              enabled: widget.enabled,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.url],
              autocorrect: false,
              enableSuggestions: false,
              decoration: const prism.InputDecoration(
                hintText: 'https://dav.example.com/remote.php/dav/files/name',
                hintMaxLines: 1,
                prefixIcon: GlyphIcon(AppGlyphs.cloudSync, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ConnectionField(
            label: '用户名',
            child: prism.TextField(
              key: const ValueKey('webdav-username-field'),
              controller: widget.usernameController,
              enabled: widget.enabled,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              autocorrect: false,
              enableSuggestions: false,
              decoration: const prism.InputDecoration(
                hintText: '输入用户名',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ConnectionField(
            label: '密码或应用密码',
            child: prism.TextField(
              key: const ValueKey('webdav-password-field'),
              controller: widget.passwordController,
              enabled: widget.enabled,
              obscureText: !_passwordVisible,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              onSubmitted: widget.enabled ? (_) => widget.onSubmitted() : null,
              decoration: prism.InputDecoration(
                hintText: '输入密码或应用密码',
                prefixIcon: const GlyphIcon(AppGlyphs.lock, size: 20),
                suffixIcon: prism.IconButton(
                  tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
                  onPressed: widget.enabled
                      ? () =>
                            setState(() => _passwordVisible = !_passwordVisible)
                      : null,
                  icon: GlyphIcon(
                    _passwordVisible ? Glyphs.eyeOff : Glyphs.eye,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConnectionField extends StatelessWidget {
  const _ConnectionField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          label,
          style: prism.AppTextStyle.subheadline
              .of(context)
              .copyWith(
                color: prism.Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      Semantics(label: label, child: child),
    ],
  );
}
