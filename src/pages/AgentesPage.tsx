/**
 * Página unificada de configuração dos agentes.
 * 3 abas top-level:
 *   - Agent Start: configs específicas (foto apresentação, re-apresentação) → placeholder na fase 1
 *   - Agent Closing: cupons automáticos
 *   - Dados: chunks da knowledge base (página antiga DadosAgentsPage)
 */
import { useState } from 'react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import DadosAgentsPage from './DadosAgentsPage';
import { CuponsManager } from '@/components/agentes/CuponsManager';
import { AgentStartConfig } from '@/components/agentes/AgentStartConfig';
import { ApresentacaoConfig } from '@/components/agentes/ApresentacaoConfig';

export default function AgentesPage() {
  const [tab, setTab] = useState<'apresentacao' | 'start' | 'closing' | 'dados'>('apresentacao');

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold">🤖 Agentes</h1>
        <p className="text-xs text-muted-foreground">
          Configurações dos agentes Start e Closing + base de conhecimento.
        </p>
      </div>

      <Tabs value={tab} onValueChange={(v) => setTab(v as any)}>
        <TabsList className="grid grid-cols-4 w-full max-w-2xl">
          <TabsTrigger value="apresentacao">1ª Apresentação</TabsTrigger>
          <TabsTrigger value="start">Agent Start</TabsTrigger>
          <TabsTrigger value="closing">Agent Closing</TabsTrigger>
          <TabsTrigger value="dados">Dados</TabsTrigger>
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
