/**
 * Página unificada de configuração dos agentes.
 * 3 abas top-level:
 *   - Agent Start: configs específicas (foto apresentação, re-apresentação) → placeholder na fase 1
 *   - Agent Closing: cupons automáticos
 *   - Dados: chunks da knowledge base (página antiga DadosAgentsPage)
 */
import { useState } from 'react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Bot } from 'lucide-react';
import DadosAgentsPage from './DadosAgentsPage';
import { CuponsManager } from '@/components/agentes/CuponsManager';
import { AgentStartConfig } from '@/components/agentes/AgentStartConfig';
import { ApresentacaoConfig } from '@/components/agentes/ApresentacaoConfig';

export default function AgentesPage() {
  const [tab, setTab] = useState<'apresentacao' | 'start' | 'closing' | 'dados'>('apresentacao');

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <div className="rounded-xl p-2 bg-primary/10 shrink-0">
          <Bot className="w-5 h-5 text-primary" />
        </div>
        <div>
          <h1 className="text-2xl font-display font-bold tracking-tight">Agentes</h1>
          <p className="text-xs text-muted-foreground">
            Configurações dos agentes Start e Closing + base de conhecimento.
          </p>
        </div>
      </div>

      <Tabs value={tab} onValueChange={(v) => setTab(v as any)}>
        <TabsList className="bg-muted/60 rounded-full p-1 h-auto flex-wrap justify-start">
          <TabsTrigger value="apresentacao" className="rounded-full px-4 py-1.5 data-[state=active]:bg-background data-[state=active]:shadow-sm">1ª Apresentação</TabsTrigger>
          <TabsTrigger value="start" className="rounded-full px-4 py-1.5 data-[state=active]:bg-background data-[state=active]:shadow-sm">Agent Start</TabsTrigger>
          <TabsTrigger value="closing" className="rounded-full px-4 py-1.5 data-[state=active]:bg-background data-[state=active]:shadow-sm">Agent Closing</TabsTrigger>
          <TabsTrigger value="dados" className="rounded-full px-4 py-1.5 data-[state=active]:bg-background data-[state=active]:shadow-sm">Dados</TabsTrigger>
        </TabsList>

        <TabsContent value="apresentacao" className="mt-4">
          <ApresentacaoConfig />
        </TabsContent>

        <TabsContent value="start" className="mt-4">
          <AgentStartConfig />
        </TabsContent>

        <TabsContent value="closing" className="mt-4">
          <CuponsManager />
        </TabsContent>

        <TabsContent value="dados" className="mt-4">
          {/* Reusa página existente de chunks */}
          <DadosAgentsPage />
        </TabsContent>
      </Tabs>
    </div>
  );
}
