/// 照片 → `mindnet.run/1`：TRANSCRIBE 里"要调模型"的那半段。
///
/// 轮次六十六 只做了确定性的那一半（`transcribe_run.dart`：给提示词、校验
/// 请求、说人话），照片本身还没有任何一段代码碰过它 —— 用户得自己把提示词
/// 复制到别的模型里，再把答案贴回来。这里补上那一步：**把照片和提示词一起
/// 发给有视觉能力的模型，把它的回话读成一份 run 请求**。
///
/// 三条纪律（与 `docs/AI_DESIGN.md` 一致）：
///
///  1. 只读：不写库、不执行请求。执行（真的跑进引擎）是另一件事。
///  2. 没配模型就不发（`adapter == null` ⇒ 直接说"发不出去"，绝不偷偷联网）。
///  3. 失败四态都返回结果对象、不抛异常：没模型 / 图不能用 / 模型这一轮失败 /
///     回话读不成请求。界面要能把"为什么没读出来"原样说给用户听。
library;

import 'dart:typed_data';

import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/transcribe_run.dart';
import '../../ai/domain/model_adapter.dart';
import '../../ai/domain/vision_payload.dart';

/// 为什么这张照片没能变成一份请求。
enum PhotoTranscribeProblem {
  /// 没配模型（离线，或者没填 key）：照片发不出去。
  notConfigured,

  /// 压缩重编码之后仍然超过硬上限。
  imageTooLarge,

  /// `dart:ui` 读不了这个文件（不是图片，或是不支持的格式）。
  imageUnreadable,

  /// 模型这一轮就失败了（网络 / HTTP / 额度）。
  modelFailed,

  /// 模型回了，但一个字都没写。
  emptyAnswer,

  /// 模型回了，但里面没有能读成 `mindnet.run/1` 的东西。
  unreadableAnswer,
}

/// 一次"照片 → 请求"的结果。
sealed class PhotoTranscribeResult {
  const PhotoTranscribeResult();
}

/// 读出来了：`report.ok` 说的是这份请求**合不合法**，不是"模型答得好不好"。
class PhotoTranscribeReport extends PhotoTranscribeResult {
  const PhotoTranscribeReport({
    required this.request,
    required this.report,
    required this.rawText,
    required this.width,
    required this.height,
  });

  /// 解码出来的原件 —— 界面要能拿它去试跑一遍（只读演练，
  /// `rehearseRun`）。带上它，是为了让"这份请求"只有一处解析：
  /// 界面不该把 [rawText] 再解一遍（`D2`：两次解析两份真相）。
  final MaterialRunRequest request;

  /// `io_check` 的输出 + TRANSCRIBE 自己的建议（出处、置信度的提醒在
  /// `report.warnings` 里）。
  final TranscribeReport report;

  /// 模型的原话 —— 留全文，让用户能自己核对（也方便复制去别处）。
  final String rawText;

  /// 真正发出去的那张图的尺寸（不是原图：编码时压过）。
  final int width;
  final int height;
}

/// 没读出来。[message] 是人话，界面直接显示。
class PhotoTranscribeFailure extends PhotoTranscribeResult {
  const PhotoTranscribeFailure(
    this.problem,
    this.message, {
    this.rawText,
  });

  final PhotoTranscribeProblem problem;
  final String message;

  /// 模型的原话（有时有：读不成请求时留着它，用户能看出来模型跑偏在哪）。
  final String? rawText;
}

/// 把一张照片交给有视觉能力的模型，把它的话读成一份 `mindnet.run/1`。
///
/// [inventory] 是【图清单】（节点 id → 人话名字），会原样填进提示词；
/// [existingNodeIds] / [existingEdgeIds] 用来查"有没有发明 id"。
///
/// 只读：除了这一次模型调用以外什么都不做。
Future<PhotoTranscribeResult> transcribePhoto({
  required ModelAdapter? adapter,
  required Uint8List image,
  required List<TranscribeInventoryEntry> inventory,
  Set<String> existingNodeIds = const <String>{},
  Set<String> existingEdgeIds = const <String>{},
  String? graphName,
  String? note,
  VisionImageEncoder encoder = const VisionImageEncoder(),
}) async {
  if (adapter == null) {
    return const PhotoTranscribeFailure(
      PhotoTranscribeProblem.notConfigured,
      '还没有可用的模型（离线，或者没填 key）：这张照片发不出去。'
      '先在 AI 设置里配好模型。',
    );
  }

  final encoded = await encoder.encode(image);
  if (encoded is VisionImageRejected) {
    return switch (encoded.code) {
      ImageFailureCode.tooLarge => const PhotoTranscribeFailure(
          PhotoTranscribeProblem.imageTooLarge,
          '这张照片压到长边 1280 之后还是超过 4 MiB：换一张小一点的，'
          '或者先裁掉多余的部分。',
        ),
      ImageFailureCode.unreadable => const PhotoTranscribeFailure(
          PhotoTranscribeProblem.imageUnreadable,
          '这不是能读的图片（PNG / JPEG 都行）：换一张试试。',
        ),
    };
  }
  final ready = encoded as VisionImageReady;

  final prompt = buildTranscribePrompt(
    inventory: inventory,
    graphName: graphName,
    note: note,
  );

  final buffer = StringBuffer();
  String? failure;
  // 工具列表是空的：这一步只让模型**说话**，它想调什么工具都无处可调。
  await for (final event in adapter.runTurn(
    messages: <ChatMessage>[
      ChatMessage.user(prompt, images: <ChatImagePart>[ready.toPart()]),
    ],
    tools: const <ModelToolSpec>[],
  )) {
    switch (event) {
      case ModelTextDelta(:final text):
        buffer.write(text);
      case ModelFailure(:final message):
        failure = message;
      case ModelToolCall():
      case ModelTurnDone():
        break;
    }
  }

  final raw = buffer.toString().trim();
  if (failure != null) {
    return PhotoTranscribeFailure(
      PhotoTranscribeProblem.modelFailed,
      '模型这一轮没走完：$failure',
      rawText: raw.isEmpty ? null : raw,
    );
  }
  if (raw.isEmpty) {
    return const PhotoTranscribeFailure(
      PhotoTranscribeProblem.emptyAnswer,
      '模型什么都没写：再试一次，或者看看 AI 设置里的模型名。',
    );
  }

  final MaterialRunRequest request;
  try {
    request = decodeRunRequest(extractJsonObject(raw));
  } on FormatException catch (error) {
    return PhotoTranscribeFailure(
      PhotoTranscribeProblem.unreadableAnswer,
      '模型写的东西读不成一份 run 请求：${error.message}',
      rawText: raw,
    );
  }

  return PhotoTranscribeReport(
    request: request,
    report: reviewTranscribedRun(
      request,
      existingNodeIds: existingNodeIds,
      existingEdgeIds: existingEdgeIds,
    ),
    rawText: raw,
    width: ready.width,
    height: ready.height,
  );
}

/// 从模型的原话里取出那个对象：整段就是 JSON 最好；不然取第一个 `{` 到最后一个
/// `}` —— AI 常常把 JSON 包在代码围栏里，或者前后加一句"这是结果"。
///
/// 取不出来就原样返回：让 `decodeRunRequest` 去说那句人话的错误，不在这里
/// 编一套新的。
String extractJsonObject(String text) {
  final trimmed = text.trim();
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return trimmed;
  }
  return trimmed.substring(start, end + 1);
}
