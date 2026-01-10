import 'package:flutter_dotenv/flutter_dotenv.dart';

String get giphyApiKey => dotenv.env['GIPHY_API_KEY'] ?? '';
