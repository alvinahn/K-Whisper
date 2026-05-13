import Foundation

enum DefaultModels {
    // Groq Llama models on LPU hardware — fastest TTFT in 2026.
    static let groqLlamaInstant   = "llama-3.1-8b-instant"      // ~50ms TTFT, ~100-250ms total
    static let groqLlamaVersatile = "llama-3.3-70b-versatile"   // ~150ms TTFT, ~250-500ms total

    // Other providers (kept as alternatives users can pick).
    static let claudeHaiku    = "claude-haiku-4-5"
    static let claudeSonnet   = "claude-sonnet-4-5"
    static let claudeOpus     = "claude-opus-4-5"
    static let openAIChat     = "gpt-4o-mini"
    static let geminiFlashLite = "gemini-2.5-flash-lite"
    static let geminiFlash    = "gemini-2.5-flash"
}

enum DefaultModes {
    static let all: [Mode] = [
        Mode(
            id: "default-cleanup",
            name: "Default cleanup",
            systemPrompt: """
            You receive a speech-to-text transcript. Return a corrected version, matching the input language (English or Korean).

            ABSOLUTE PRIORITY — PRESERVE THE SPEAKER'S LINGUISTIC IDENTITY
            The speaker's register, dialect (사투리/방언), generational style, word endings, repetitions, contractions, and word choices are intentional — they reflect WHO the speaker is. Your job is ONLY to fix words that STT transcribed incorrectly. When uncertain, leave the text unchanged. Over-cleaning is a WORSE error than under-cleaning. Normalizing a regional/casual/generational form to "standard" 표준어 is wrong — it erases the speaker.

            Korean — DO NOT change any of these:
            - Dialect / regional speech (사투리, 방언): NEVER normalize regional Korean to 표준어 (Seoul standard). Regional verb endings, regional particles, regional vocabulary, regional vowel/consonant variations — all are valid Korean and must be preserved verbatim. Do NOT "fix" dialect features to their Seoul-standard equivalents. The same applies to generational vocabulary (younger-generation slang, older idioms) — keep it as-is.
            - Register: never convert 반말 to 존댓말 or vice versa. If the input is 반말 (해, 했어, 같애, 됐어, 그래, 그치, 가자), keep 반말. If 존댓말 (해요, 했어요, 같아요, 됐어요), keep 존댓말. Mixed register inside one transcript is also intentional — leave it.
            - Colloquial verb endings: keep 같애, 됐어, 그래, 그치, 했더라, 하더라구, ~네, ~잖아, ~거든, ~더라고 as transcribed. Do NOT normalize them to written-style forms like 같다, 되었다, 그렇다.
            - Suggestive / hedging endings (~ㄴ데, ~는데, ~은데): these are a DIFFERENT speech act from ~네 / ~다 / ~지. 같은데, 그런데, 했는데, 됐는데, 였는데 imply "I'm wondering / I'm suggesting / hedging" — NEVER rewrite them as 같네, 그렇네, 했네, 됐네, 였네 (which mean "I'm observing / noting"). Preserve the ~데 form verbatim. The same applies to 같은데요, 했는데요 in 존댓말.
            - Verb endings encode speech-act meaning — preserve them as classes: ~네(관찰/notice), ~데/~는데(추측·제안/hedge), ~지/~잖아(확인/seek-agreement), ~더라(회상/recall), ~을걸/~겠지(추측/guess). Never swap one class for another.
            - Punctuation as transcribed: if STT writes `?`, `!`, `~`, or `...`, keep them. NEVER strip a trailing `?` even when the verb form looks declarative — the `?` carries the speaker's rising intonation and the soft-questioning meaning.
            - Emphatic repetition: keep doubled or tripled words exactly (해줘봐봐, 빨리빨리, 정말정말, 진짜진짜, 막막).
            - Contractions / short forms: keep 뭐, 이거, 그거, 저거, 왜, 어디 as transcribed. Do not expand to 무엇, 이것, 어디에 등.
            - Word insertion: do NOT add words the speaker did not say. Common offenders to NEVER insert: 그냥, 좀, 이제, 한번, 막, 뭐, 약간, 진짜.
            - Sentence merging or splitting: if the speaker paused mid-thought, keep the pause. Do not stitch fragments into one polished sentence.

            Korean — what TO fix (only these):
            - STT misrecognitions where Whisper split a single compound verb. For example, a transcript that reads 미치고 버렸네 most likely should be the merged form 미쳐버렸네 — correct it.
            - Particles (이/가, 은/는, 을/를, 에/에서, 으로/로) only when the chosen particle makes the sentence grammatically broken AND the correct choice is unambiguous from context.
            - Particle agreement: 이/가, 은/는, 을/를, 와/과 must agree with the preceding syllable's final consonant (받침). If you see a clear mismatch (e.g. 셔니이 — 셔니 ends in vowel, particle should be 가; or 알빈가 — 알빈 ends in consonant, particle should be 이), correct the particle. This is the ONE permitted exception to the "preserve verb endings" rule.
            - Obvious homophone errors where context makes the correct word certain (e.g. 같이 vs 가치, 시키다 vs 식히다, 부치다 vs 붙이다).

            English correction:
            - Remove filler words (um, uh, like, you know) only when they are clearly fillers.
            - Fix punctuation and capitalization.
            - Do NOT paraphrase. Do NOT change word choices or register.

            STRICT OUTPUT FORMAT:
            Reply with ONLY the corrected transcript, EXACTLY ONCE. No commentary. No quotation marks. No arrows. No "before / after" or "X → Y" listing. Do not include the original input alongside the result.
            """,
            provider: .groq,
            model: DefaultModels.groqLlamaVersatile,  // 70B handles Korean morphology far better than 8B
            temperature: 0.1,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "email",
            name: "Email",
            systemPrompt: "Rewrite the transcript as a clear, concise email body. Match input language. No greeting/sign-off unless dictated. Output ONLY the email body.",
            provider: .groq,
            model: DefaultModels.groqLlamaVersatile,
            temperature: 0.3,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "slack",
            name: "Slack",
            systemPrompt: "Rewrite as a brief, casual Slack message. Match input language. No greeting/sign-off. One or two sentences. Output ONLY the message.",
            provider: .groq,
            model: DefaultModels.groqLlamaInstant,
            temperature: 0.4,
            maxTokens: 512,
            isBuiltIn: true
        ),
        Mode(
            id: "ko-to-en",
            name: "Korean → English",
            systemPrompt: "Translate Korean to natural, idiomatic English. Keep technical terms in English. Match the register of the source. Output ONLY the translation.",
            provider: .groq,
            model: DefaultModels.groqLlamaVersatile,
            temperature: 0.2,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "en-to-ko",
            name: "English → Korean",
            systemPrompt: "Translate English to natural Korean. Default tone: {KOREAN_TONE}. Keep proper nouns and technical terms in original form. Output ONLY the translation.",
            provider: .groq,
            model: DefaultModels.groqLlamaVersatile,
            temperature: 0.2,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "code-comment",
            name: "Code comment",
            systemPrompt: "Convert to a terse code comment. One line if possible. No markdown, no quotes. English unless the speaker asked for Korean. Output ONLY the comment text without comment markers.",
            provider: .groq,
            model: DefaultModels.groqLlamaInstant,
            temperature: 0.2,
            maxTokens: 256,
            isBuiltIn: true
        ),
        Mode(
            id: "raw",
            name: "Raw (no post-processing)",
            systemPrompt: "",
            provider: .none,
            model: "",
            temperature: 0,
            maxTokens: 0,
            isBuiltIn: true
        )
    ]
}
