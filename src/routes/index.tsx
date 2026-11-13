import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Cenin Studio · Tatuagem" },
      { name: "description", content: "Cenin Studio — estúdio de tatuagem. Conheça o trabalho e agende sua sessão." },
      { property: "og:title", content: "Cenin Studio · Tatuagem" },
      { property: "og:description", content: "Estúdio de tatuagem Cenin Studio. Agende sua sessão." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

function Index() {
  return (
    <iframe
      src="/cenin.html?v=gallery-restored-8898ee2"
      title="Cenin Studio · Tatuagem"
      className="fixed inset-0 h-full w-full border-0 bg-background"
    />
  );
}
