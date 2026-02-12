#!/usr/bin/env python3
"""Patch llama_stack tool_executor.py to pass through file attributes.

Llama Stack 0.3.5 has a bug where _build_result_messages hardcodes
`filename=doc_id` and `attributes={}` for file_search_call results,
even though the actual attributes are available from the vector store
search.  This patch:

1.  Adds `search_result_attributes` to the metadata returned by
    `_execute_knowledge_search_via_vector_store`.
2.  Updates `_build_result_messages` to use `citation_files` and
    `search_result_attributes` from metadata instead of the hardcoded
    values.
3.  Normalises attributes so that `doc_url` is set from `docs_url` if
    missing, and uses the `title` attribute as the filename when
    available (instead of the raw compound filename string).

Usage (typically called from a Containerfile):
    python patches/fix_tool_executor_attributes.py
"""

import importlib
import inspect
import sys


def _find_tool_executor_path() -> str:
    """Return the filesystem path to the installed tool_executor.py."""
    mod = importlib.import_module(
        "llama_stack.providers.inline.agents.meta_reference.responses.tool_executor"
    )
    path = inspect.getfile(mod)
    print(f"[patch] Found tool_executor.py at: {path}")
    return path


def _patch_file(path: str) -> None:
    with open(path, "r") as f:
        source = f.read()

    original = source  # keep a copy for comparison

    # ---------------------------------------------------------------
    # Patch 1 – _execute_knowledge_search_via_vector_store
    #   Add search_result_attributes to the metadata dict.
    # ---------------------------------------------------------------
    if "search_result_attributes" not in source:
        source = source.replace(
            '        return ToolInvocationResult(\n'
            '            content=content_items,\n'
            '            metadata={\n'
            '                "document_ids": [r.file_id for r in search_results],\n'
            '                "chunks": [r.content[0].text if r.content else "" for r in search_results],\n'
            '                "scores": [r.score for r in search_results],\n'
            '                "citation_files": citation_files,\n'
            '            },\n'
            '        )',
            '        search_result_attributes = [r.attributes or {} for r in search_results]\n'
            '\n'
            '        return ToolInvocationResult(\n'
            '            content=content_items,\n'
            '            metadata={\n'
            '                "document_ids": [r.file_id for r in search_results],\n'
            '                "chunks": [r.content[0].text if r.content else "" for r in search_results],\n'
            '                "scores": [r.score for r in search_results],\n'
            '                "citation_files": citation_files,\n'
            '                "search_result_attributes": search_result_attributes,\n'
            '            },\n'
            '        )',
        )
        print("[patch] Injected search_result_attributes into metadata dict")
    else:
        print("[patch] search_result_attributes already present – skipping patch 1")

    # ---------------------------------------------------------------
    # Patch 2 – _build_result_messages
    #   Use citation_files and search_result_attributes from metadata,
    #   normalise attributes (doc_url alias), and use title attribute
    #   as filename.
    # ---------------------------------------------------------------

    # 2a. Replace the entire results-building block
    old_block = (
        '                if result and "document_ids" in result.metadata:\n'
        '                    message.results = []\n'
        '                    for i, doc_id in enumerate(result.metadata["document_ids"]):\n'
        '                        text = result.metadata["chunks"][i] if "chunks" in result.metadata else None\n'
        '                        score = result.metadata["scores"][i] if "scores" in result.metadata else None\n'
        '                        message.results.append(\n'
        '                            OpenAIResponseOutputMessageFileSearchToolCallResults(\n'
        '                                file_id=doc_id,\n'
        '                                filename=doc_id,\n'
        '                                text=text,\n'
        '                                score=score,\n'
        '                                attributes={},\n'
        '                            )\n'
        '                        )'
    )
    new_block = (
        '                if result and "document_ids" in result.metadata:\n'
        '                    sr_citation_files = result.metadata.get("citation_files", {})\n'
        '                    sr_attributes = result.metadata.get("search_result_attributes", [])\n'
        '                    message.results = []\n'
        '                    for i, doc_id in enumerate(result.metadata["document_ids"]):\n'
        '                        text = result.metadata["chunks"][i] if "chunks" in result.metadata else None\n'
        '                        score = result.metadata["scores"][i] if "scores" in result.metadata else None\n'
        '                        attrs = dict(sr_attributes[i]) if i < len(sr_attributes) else {}\n'
        '                        # Normalise: add doc_url from docs_url if not already present\n'
        '                        if "doc_url" not in attrs and "docs_url" in attrs:\n'
        '                            attrs["doc_url"] = attrs["docs_url"]\n'
        '                        # Use clean title from attributes; fall back to citation_files then doc_id\n'
        '                        display_name = attrs.get("title") or sr_citation_files.get(doc_id, doc_id)\n'
        '                        message.results.append(\n'
        '                            OpenAIResponseOutputMessageFileSearchToolCallResults(\n'
        '                                file_id=doc_id,\n'
        '                                filename=display_name,\n'
        '                                text=text,\n'
        '                                score=score,\n'
        '                                attributes=attrs,\n'
        '                            )\n'
        '                        )'
    )

    if "sr_citation_files" not in source:
        count = source.count(old_block)
        if count == 0:
            print("[patch] WARNING: Could not find the results-building block to replace")
            print("[patch] The tool_executor.py may have been modified. Manual patching required.")
            sys.exit(1)
        source = source.replace(old_block, new_block)
        print("[patch] Replaced results-building block with normalised version")
    else:
        print("[patch] sr_citation_files already present – skipping patch 2")

    if source == original:
        print("[patch] No changes were needed – file already patched")
        return

    with open(path, "w") as f:
        f.write(source)

    print(f"[patch] Successfully patched {path}")


def main() -> None:
    try:
        path = _find_tool_executor_path()
        _patch_file(path)
    except Exception as e:
        print(f"[patch] ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
