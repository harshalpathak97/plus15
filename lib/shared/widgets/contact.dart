import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';

/// Opens an email to us, or says where to write when there's no mail app.
Future<void> openMail(BuildContext context,
    {required String subject, required String body}) async {
  HapticFeedback.lightImpact();
  // Encoded by hand: Uri.queryParameters turns spaces into "+", which mail
  // apps show literally.
  final uri = Uri.parse('mailto:${AppConstants.contactEmail}'
      '?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
  final ok = await launchUrl(uri).catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('No mail app found. Email us at ${AppConstants.contactEmail}'),
      ));
  }
}

/// Opens [url] in the browser.
Future<void> openLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
      .catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Couldn't open $url")));
  }
}
