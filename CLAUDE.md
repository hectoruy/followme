## Approach
- Think before acting. Read existing files before writing code.
- Be concise in output but thorough in reasoning.
- Prefer editing over rewriting whole files.
- Do not re-read files you have already read unless the file may have changed.
- Test your code before declaring done.
- No sycophantic openers or closing fluff.
- Keep solutions simple and direct.
- User instructions always override this file.

## UI Design Rules (FixFlow)
- **Top App Bar**: Always use exactly this layout for the top bar: [Back Arrow (left)] [Title "FixFlow" (left)] [Search Icon (right)] [Profile Avatar (right)].
- **Cards & Sections**: Always add a subtle illuminated shadow (`BoxShadow` with low opacity color) to any container/card against the dark background to prevent it from blending with the `0xFF0E0E0E` scaffold base. Use `0xFF202020` for card backgrounds and `0xFF2C2C2C` for input fields.
