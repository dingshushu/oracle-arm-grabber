// Cloudflare Worker：用 GitHub App 身份，每被调用一次就触发一次 workflow_dispatch
// 为什么需要它：cron-job.org 只是个 HTTP 定时器，不会签 JWT；而 GitHub App 调用 API 必须先
// 用私钥签 JWT -> 换 installation token -> 才能调 dispatch。Worker 负责这三步。
//
// 部署（任选其一）：
//   A) Wrangler：把本文件放 src/index.js，旁边放 wrangler.toml（见同目录），然后 `wrangler deploy`
//   B) 控制台：https://dash.cloudflare.com -> Workers -> Create -> 粘贴本文件 -> Deploy
//
// 需要的 Secrets / 环境变量（在 Worker 设置里填，不要硬编码）：
//   GH_APP_ID          GitHub App 的 App ID（数字）
//   GH_APP_PEM         App 私钥，需 PKCS#8 格式 PEM（GitHub 给的是 PKCS#1，要用 openssl 转，见下）
//   GH_INSTALLATION_ID 安装 ID（数字）
//   GH_REPO            dingshushu/oracle-arm-grabber
//   GH_WORKFLOW        主 workflow 文件（默认 grab-oracle-arm.yml）
//   GH_WORKFLOW_AMD    （可选）AMD workflow 文件（grab-amd.yml），设置后可用 ?target=amd/all 触发
//   GH_REF             main
//   WORKER_SECRET      （可选）自定义一个字符串；填了之后调用必须带 ?secret=xxx，防止被人乱触发
//
// 调用方式：
//   ?secret=xxx             触发 ARM（默认行为，兼容旧 cron 任务）
//   ?secret=xxx&target=amd  只触发 AMD（需已设置 GH_WORKFLOW_AMD）
//   ?secret=xxx&target=all  两个都触发

// ---------- 工具函数 ----------
function b64url(input) {
  const b64 = typeof input === "string"
    ? btoa(unescape(encodeURIComponent(input)))
    : btoa(String.fromCharCode(...input));
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// PEM -> DER (ArrayBuffer)
function pemToDer(pem) {
  const b64 = pem.replace(/-----BEGIN[^-]+-----/, "")
                 .replace(/-----END[^-]+-----/, "")
                 .replace(/\s+/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

export default {
  async fetch(request, env) {
    // 可选的保护：若设置了 WORKER_SECRET，必须带正确的 ?secret=
    if (env.WORKER_SECRET) {
      const url = new URL(request.url);
      if (url.searchParams.get("secret") !== env.WORKER_SECRET) {
        return new Response("forbidden", { status: 403 });
      }
    }

    // target 参数：arm=只触发ARM(默认) | amd=只触发AMD | all=两个都触发
    const target = new URL(request.url).searchParams.get("target") || "arm";

    const APP_ID = env.GH_APP_ID;
    const PEM = env.GH_APP_PEM;
    const INSTALL_ID = env.GH_INSTALLATION_ID;
    const REPO = env.GH_REPO || "dingshushu/oracle-arm-grabber";
    const REF = env.GH_REF || "main";

    // GitHub API 强制要求 User-Agent 头，Cloudflare Worker 的 fetch 默认不带，必须显式加
    const UA = "oracle-arm-grabber-dispatch";

    try {
      // 1) 用 App 私钥签一个 JWT
      const now = Math.floor(Date.now() / 1000);
      const header = { alg: "RS256", typ: "JWT" };
      const payload = { iat: now - 60, exp: now + 540, iss: APP_ID };
      const signInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
      const key = await crypto.subtle.importKey(
        "pkcs8",
        pemToDer(PEM),
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["sign"]
      );
      const sig = await crypto.subtle.sign(
        { name: "RSASSA-PKCS1-v1_5" },
        key,
        new TextEncoder().encode(signInput)
      );
      const jwt = `${signInput}.${b64url(new Uint8Array(sig))}`;

      // 2) 换 installation access token
      const tokResp = await fetch(
        `https://api.github.com/app/installations/${INSTALL_ID}/access_tokens`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${jwt}`,
            Accept: "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": UA,
          },
        }
      );
      if (!tokResp.ok) {
        const t = await tokResp.text();
        return new Response(`token_fail ${tokResp.status} ${t}`, { status: 502 });
      }
      const { token } = await tokResp.json();

      // 3) 触发 workflow_dispatch（按 target 参数选择一个或多个 workflow）
      const workflows = [];
      if (target === "arm" || target === "all") {
        workflows.push(env.GH_WORKFLOW || "grab-oracle-arm.yml");
      }
      if (target === "amd" || target === "all") {
        if (env.GH_WORKFLOW_AMD) workflows.push(env.GH_WORKFLOW_AMD);
      }
      if (workflows.length === 0) {
        return new Response(
          JSON.stringify({ ok: false, error: `no workflow for target=${target}（AMD 需设置 GH_WORKFLOW_AMD 变量）` }),
          { status: 400, headers: { "content-type": "application/json" } }
        );
      }

      const results = [];
      for (const wf of workflows) {
        const dispResp = await fetch(
          `https://api.github.com/repos/${REPO}/actions/workflows/${wf}/dispatches`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${token}`,
              Accept: "application/vnd.github+json",
              "Content-Type": "application/json",
              "X-GitHub-Api-Version": "2022-11-28",
              "User-Agent": UA,
            },
            body: JSON.stringify({ ref: REF }),
          }
        );
        results.push({ workflow: wf, gh_status: dispResp.status });
      }

      const allOk = results.every((r) => r.gh_status >= 200 && r.gh_status < 300);
      return new Response(JSON.stringify({ ok: allOk, results }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    } catch (e) {
      return new Response(`error ${e.message}`, { status: 500 });
    }
  },
};
