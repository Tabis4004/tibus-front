import 'package:supabase_flutter/supabase_flutter.dart';

/// Message d'erreur lisible pour l'utilisateur — évite d'afficher le dump
/// brut d'une PostgrestException ("PostgrestException(message: ..., code:
/// ..., details: ..., hint: null)") dans un SnackBar/toast : on ne garde
/// que le champ `message`, déjà rédigé en français côté RPC (RAISE
/// EXCEPTION '...'). Pour toute autre erreur, on retombe sur le
/// comportement existant (toString, sans le préfixe "Exception: ").
String friendlyError(Object error) {
  if (error is PostgrestException) {
    return error.message;
  }
  return error.toString().replaceFirst('Exception: ', '');
}
