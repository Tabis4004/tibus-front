{\rtf1\ansi\ansicpg1252\cocoartf2822
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx566\tx1133\tx1700\tx2267\tx2834\tx3401\tx3968\tx4535\tx5102\tx5669\tx6236\tx6803\pardirnatural\partightenfactor0

\f0\fs24 \cf0 import 'package:flutter/material.dart';\
import 'package:flutter/foundation.dart' show kIsWeb;\
\
class PrintPage extends StatelessWidget \{\
  const PrintPage(\{Key? key\}) : super(key: key);\
\
  // Votre fonction d'impression plac\'e9e ici\
  void printReceipt() \{\
    if (kIsWeb) \{\
      // Code alternatif pour le Web\
      print("Impression web directe non support\'e9e par ce plugin natif.");\
    \} else \{\
      // Code natif mobile (Android/iOS) avec le SDK Xprinter\
      // XprinterSdk.print(...);\
    \}\
  \}\
\
  @override\
  Widget build(BuildContext context) \{\
    return Scaffold(\
      appBar: AppBar(title: Text("Impression")),\
      body: Center(\
        child: ElevatedButton(\
          onPressed: printReceipt, // Appel de la fonction au clic\
          child: Text("Imprimer le re\'e7u"),\
        ),\
      ),\
    );\
  \}\
\}}