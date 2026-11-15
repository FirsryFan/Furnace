import 'model_adapter.dart';

/// The images attached to the current user turn, shared between the agent loop
/// and tools that need the same pictures.
///
/// The agent loop is the only writer; a tool reads a snapshot. This exists
/// because a tool call carries arguments, not the user message's attachment
/// list, and the student solver needs the figure the user just attached.
class StudentSolverContext {
  List<ChatImagePart> _images = const [];

  List<ChatImagePart> get images => _images;

  void setImages(Iterable<ChatImagePart> images) {
    _images = List.unmodifiable(images);
  }

  void clear() {
    _images = const [];
  }
}
